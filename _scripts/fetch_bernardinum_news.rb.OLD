require 'dotenv/load'
require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

STORE_URL = ENV['BERNARDINUM_STORE_URL']
CLIENT_ID = ENV['BERNARDINUM_CLIENT_ID']
CLIENT_SECRET = ENV['BERNARDINUM_CLIENT_SECRET']

DATA_DIR = '_data'.freeze

def get_access_token(store_url, client_id, client_secret)
  uri = URI("#{store_url}/webapi/rest/auth")
  req = Net::HTTP::Post.new(uri)
  req.basic_auth(client_id, client_secret)
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess); raise "Błąd autoryzacji: #{res.code} #{res.message} - #{res.body}"; end
  JSON.parse(res.body)['access_token']
end

def get_news(store_url, token)
  uri = URI("#{store_url}/webapi/rest/news")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{token}"
  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess); raise "Błąd pobierania aktualności: #{res.code} #{res.message} - #{res.body}"; end
  JSON.parse(res.body)['list']
end

begin
  puts "INFO: Autoryzacja w API Shoper..."
  access_token = get_access_token(STORE_URL, CLIENT_ID, CLIENT_SECRET)
  raise "Nie udało się uzyskać tokena dostępowego." if access_token.nil?
  
  puts "INFO: Autoryzacja pomyślna. Pobieranie aktualności..."
  news_list = get_news(STORE_URL, access_token)
  
  # Przetwarzanie listy aktualności zgodnie z zagnieżdżoną strukturą API
  processed_news = news_list.map do |news_item|
    # 'news_item' to główny obiekt aktualności (ten z 'gfx' i 'translations')
    
    # Krok 1: Wchodzimy do obiektu z tłumaczeniami dla języka polskiego
    translation = news_item['translations']['pl_PL']
    
    # Krok 2: Budujemy pełny URL do obrazka
    image_full_url = nil
    # Sprawdzamy, czy w głównym obiekcie ('news_item') istnieje pole 'gfx'
    if news_item['gfx']
      # Tworzymy pełny URL: "https://mojsklep.pl/" + "gfx/zdjecie.jpg"
      image_full_url = "#{STORE_URL}/#{news_item['gfx']}"
    end
    
    # Krok 3: Składamy wszystkie dane w jeden czysty obiekt dla Jekylla
    {
      # 'news_id' pochodzi z głównego obiektu 'news_item'
      'id' => news_item['news_id'],
      
      # 'title' pochodzi z obiektu tłumaczenia ('translation')
      'title' => translation['title'],
      
      # 'short_content' pochodzi z obiektu tłumaczenia ('translation')
      'short_content' => translation['content_short'], 
      
      # 'image_url' to nasz zbudowany pełny link do zdjęcia
      'image_url' => image_full_url,
      
      # 'link' (permalink) pochodzi z obiektu tłumaczenia ('translation')
      'link' => translation['permalink'],

      'add_date' => news_item['date'] # Dodajemy datę do sortowania
    }
  end

  # Zapis do pliku
  FileUtils.mkdir_p(DATA_DIR)
  output_path = File.join(DATA_DIR, OUTPUT_FILE)
  File.open(output_path, 'w') do |f|
    f.write(JSON.pretty_generate(processed_news))
  end
  
  puts "SUKCES: Pomyślnie zapisano #{processed_news.length} aktualności do pliku #{output_path}"

rescue StandardError => e
  puts "BŁĄD: Wystąpił krytyczny problem: #{e.message}"
  exit 1
end 