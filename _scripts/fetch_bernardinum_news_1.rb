
require 'dotenv/load'
require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

# --- Konfiguracja ---
STORE_URL      = ENV['BERNARDINUM_STORE_URL']     
API_TOKEN      = ENV['BERNARDINUM_API_TOKEN']     
DATA_DIR       = '_data'.freeze
OUTPUT_FILE    = 'news.json'.freeze
# --------------------

def debug_log(label, data)
  puts "\n=== #{label} ==="
  puts data
  puts "=== KONIEC #{label} ===\n\n"
end

def get_news(store_url, token)
  uri = URI("#{store_url}/webapi/rest/news")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{token}"

  debug_log("Żądanie NEWS", {
    url: uri.to_s,
    method: "GET",
    headers: req.to_hash
  })

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end

  debug_log("Odpowiedź NEWS", {
    code: res.code,
    message: res.message,
    headers: res.to_hash,
    body: res.body
  })

  unless res.is_a?(Net::HTTPSuccess)
    raise "Błąd pobierania aktualności: #{res.code} #{res.message} - #{res.body}"
  end

  JSON.parse(res.body)['list']
end

begin
  raise "STORE_URL nie jest ustawiony!" if STORE_URL.nil? || STORE_URL.strip.empty?
  raise "API_TOKEN nie jest ustawiony!" if API_TOKEN.nil? || API_TOKEN.strip.empty?

  puts "INFO: Pobieranie aktualności z Shoper API..."
  news_list = get_news(STORE_URL, API_TOKEN)

  processed_news = news_list.map do |news_item|
    puts "DEBUG: news_item = #{news_item.inspect}"
    translation = news_item.dig('translations', 'pl_PL')
    next nil unless translation # pomiń jeśli brak tłumaczenia
    image_full_url = news_item['gfx'] ? "#{STORE_URL}/#{news_item['gfx']}" : nil

    {
      'id'            => news_item['news_id'],
      'title'         => translation['title'],
      'short_content' => translation['content_short'],
      'image_url'     => image_full_url,
      'link'          => translation['permalink']
    }
  end.compact

  FileUtils.mkdir_p(DATA_DIR)
  output_path = File.join(DATA_DIR, OUTPUT_FILE)
  File.open(output_path, 'w') do |f|
    f.write(JSON.pretty_generate(processed_news))
  end

  puts "SUKCES: Zapisano #{processed_news.length} aktualności do pliku #{output_path}"

rescue StandardError => e
  puts "BŁĄD: #{e.message}"
  puts e.backtrace.join("\n")
  exit 1
end