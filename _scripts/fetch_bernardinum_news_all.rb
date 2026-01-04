#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'time'
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

# --- SANITIZE: usuwa znaki, które potrafią wywalić Jekyll/Psych w _data/*.json ---
def sanitize_string(val)
  return val unless val.is_a?(String)

  s = val.dup
  s = s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  # C0 control chars poza TAB/LF/CR
  s = s.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/, '')
  # C1 controls + separatory problematyczne
  s = s.gsub(/[\u007F-\u009F\u0085\u2028\u2029]/, '')
  s
end

def sanitize_object(obj)
  case obj
  when Hash
    obj.each_with_object({}) { |(k, v), h| h[k] = sanitize_object(v) }
  when Array
    obj.map { |v| sanitize_object(v) }
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
  Time.parse(str.to_s)
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

def fetch_all_news(store_url, token, limit: 200)
  all = []
  page = 1
  total_pages = nil

  loop do
    data, res = fetch_page(store_url, token, page, limit)
    list = data['list'] || []
    all.concat(list)

    total_pages ||= (res['x-shop-result-pages'] || data['pages']).to_i
    current_page = (res['x-shop-result-page'] || data['page']).to_i
    log_info("Pobrano stronę #{current_page}/#{total_pages} (rekordów: #{list.length})")

    break if total_pages > 0 && page >= total_pages
    page += 1
  end

  all
end

# --- MAIN ---
if STORE_URL.empty? || API_TOKEN.empty?
  abort "Brak ENV: BERNARDINUM_STORE_URL lub BERNARDINUM_API_TOKEN"
end

log_info("Pobieranie CAŁEJ bazy aktualności z Shoper API...")
raw_list = fetch_all_news(STORE_URL, API_TOKEN, limit: 200)

mapped = raw_list.map { |n| map_news_item(STORE_URL, n) }
mapped.sort_by! { |x| x['id'].to_i }

FileUtils.mkdir_p(File.dirname(DATA_PATH)) rescue nil
write_json_utf8(DATA_PATH, mapped)

log_info("Zapisano #{mapped.length} rekordów do #{DATA_PATH}")
