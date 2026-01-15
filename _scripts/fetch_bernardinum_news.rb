#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'date'
require 'fileutils'
require 'dotenv/load'

DATA_PATH = File.expand_path('../_data/news.json', __dir__)
STORE_URL = ENV['BERNARDINUM_STORE_URL'].to_s.strip
API_TOKEN = ENV['BERNARDINUM_API_TOKEN'].to_s.strip
DEBUG     = (ENV['BERNARDINUM_DEBUG'].to_s.strip == '1')

def log_info(msg)
  puts "INFO: #{msg}"
end

def log_warn(msg)
  warn "WARN: #{msg}"
end

def debug_log(label, obj)
  return unless DEBUG
  puts "\n=== #{label} ==="
  puts JSON.pretty_generate(obj)
  puts "=== KONIEC #{label} ===\n\n"
end

def sanitize_string(val)
  return val unless val.is_a?(String)
  s = val.dup
  s = s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  s = s.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/, '')
  s = s.gsub(/[\u007F-\u009F\u0085\u2028\u2029]/, '')
  s
end

def sanitize_object(obj)
  case obj
  when Hash
    obj.each_with_object({}) { |(k, v), h| h[k] = sanitize_object(v) }
  when Array
    obj.map { |v| h = sanitize_object(v); h }
  when String
    sanitize_string(obj)
  else
    obj
  end
end

def write_json_utf8(path, data)
  json = JSON.pretty_generate(data)
  File.open(path, 'wb') { |f| f.write(json.encode('UTF-8')) }
end

def http_request(uri, req, max_retries: 5)
  retries = 0
  begin
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 60
    http.open_timeout = 20

    res = http.request(req)

    if res.code.to_i == 429 || (500..599).include?(res.code.to_i)
      raise "HTTP #{res.code}"
    end

    res
  rescue => e
    retries += 1
    if retries <= max_retries
      sleep_s = [2**retries, 30].min
      log_warn("Retry ##{retries} po błędzie: #{e.class}: #{e.message} (sleep #{sleep_s}s)")
      sleep sleep_s
      retry
    end
    raise
  end
end

def parse_time(str)
  s = str.to_s.strip
  return nil if s.empty?

  # jeśli brak strefy w stringu, traktuj jako UTC
  if s =~ /(\+|\-)\d{2}:\d{2}\z/ || s.end_with?('Z')
    Time.parse(s)
  else
    Time.parse(s + ' UTC')
  end
rescue
  nil
end

def absolutize_url(store_url, maybe_path)
  return nil if maybe_path.nil?
  s = maybe_path.to_s.strip
  return nil if s.empty?
  return s if s =~ %r{\Ahttps?://}i

  base = store_url.sub(%r{/\z}, '')
  if s.start_with?('/')
    base + s
  else
    base + '/' + s
  end
end

def extract_first_img_src(html)
  return nil if html.nil?
  m = html.to_s.match(/<img[^>]+src=["']([^"']+)["']/i)
  m ? m[1] : nil
end

def map_news_item(store_url, n)
  id = n['news_id'].to_i
  title = n['name'].to_s
  content = n['content'].to_s
  short_content = n['short_content'].to_s
  date_str = n['date'].to_s

  img = nil
  img = n['image_url'] if n.key?('image_url')
  img = n['image'] if img.nil? && n.key?('image')
  if img.nil? || img.to_s.strip.empty?
    img = extract_first_img_src(content) || extract_first_img_src(short_content)
  end
  img_abs = absolutize_url(store_url, img)

  {
    'id' => id,
    'title' => title,
    'short_content' => short_content,
    'content' => content,
    'date' => date_str,
    'link' => nil,
    'image_url' => img_abs,
    'active' => n['active'].to_s
  }
end

def fetch_page(store_url, token, page, limit)
  uri = URI("#{store_url}/webapi/rest/news")
  uri.query = URI.encode_www_form('page' => page, 'limit' => limit)

  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{token}"
  req['Accept'] = 'application/json'

  debug_log('Żądanie NEWS', { url: uri.to_s, method: 'GET', headers: req.to_hash })

  res = http_request(uri, req)

  preview = res.body ? res.body[0, 500] : nil
  debug_log('Odpowiedź NEWS', { code: res.code, message: res.message, headers: res.to_hash, body_preview: preview })

  unless res.is_a?(Net::HTTPSuccess)
    raise "Błąd NEWS: #{res.code} #{res.message} | #{res.body}"
  end

  data = sanitize_object(JSON.parse(res.body))
  [data, res]
end

def load_existing(path)
  return [] unless File.exist?(path)
  sanitize_object(JSON.parse(File.read(path, mode: 'rb')))
rescue => e
  log_warn("Nie udało się wczytać news.json (#{e.class}: #{e.message}). Start od zera.")
  []
end

def merge_by_id(existing_arr, fetched_arr)
  by_id = {}
  existing_arr.each { |r| by_id[r['id'].to_i] = r }
  fetched_arr.each  { |r| by_id[r['id'].to_i] = r }
  merged = by_id.values
  merged.sort_by { |x| x['id'].to_i }
end

def fetch_last_days(store_url, token, days: 2, limit: 200)
  # cutoff liczony "od północy" sprzed N dni (UTC)
  cutoff =
    Time.utc(Date.today.year, Date.today.month, Date.today.day) -
    (days * 24 * 60 * 60)

  # 1) pobierz stronę 1 tylko po to, żeby poznać total_pages
  data1, res1 = fetch_page(store_url, token, 1, limit)
  total_pages = (res1['x-shop-result-pages'] || data1['pages']).to_i
  total_pages = 1 if total_pages <= 0

  log_info("API pages=#{total_pages}, cutoff=#{cutoff}")

  fetched = []

  # 2) lecimy od końca (najnowsze wpisy są na końcu)
  page = total_pages
  while page >= 1
    data, _res = fetch_page(store_url, token, page, limit)
    list = data['list'] || []
    break if list.empty?

    times  = list.map { |n| parse_time(n['date']) }.compact
    newest = times.max
    oldest = times.min

    log_info("Strona #{page}: rekordów #{list.length}, newest=#{newest}, oldest=#{oldest}")

    # jeśli nawet newest < cutoff → dalej będą tylko starsze
    break if newest && newest < cutoff

    list.each do |n|
      t = parse_time(n['date'])
      fetched << n if t && t >= cutoff
    end

    page -= 1
  end

  fetched
end

# --- MAIN ---
if STORE_URL.empty? || API_TOKEN.empty?
  abort "Brak ENV: BERNARDINUM_STORE_URL lub BERNARDINUM_API_TOKEN"
end

log_info("Aktualizacja news.json: pobieram tylko wpisy z ostatnich 2 dni i MERGE...")

existing = load_existing(DATA_PATH)

days_window = (ENV['BERNARDINUM_NEWS_DAYS'] || '14').to_i
days_window = 14 if days_window <= 0

log_info("Okno pobierania newsów: #{days_window} dni")

raw_recent = fetch_last_days(
  STORE_URL,
  API_TOKEN,
  days: days_window,
  limit: 200
)

mapped_recent = raw_recent.map { |n| map_news_item(STORE_URL, n) }

merged = merge_by_id(existing, mapped_recent)

FileUtils.mkdir_p(File.dirname(DATA_PATH))
write_json_utf8(DATA_PATH, merged)

log_info("Zapisano #{merged.length} rekordów w #{DATA_PATH} (dociągnięto/odświeżono: #{mapped_recent.length})")
