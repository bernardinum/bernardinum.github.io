require 'net/http'
require 'nokogiri'
require 'json'
require 'fileutils'
require 'open-uri'

# --- Konfiguracja ---
XML_URL = 'https://sklep5435072.homesklep.pl/console/integration/execute/name/GoogleProductSearch'.freeze
DATA_DIR = '_data'.freeze
OUTPUT_FILE = 'books.json'.freeze
# --------------------

puts "INFO: Rozpoczynam pobieranie danych produktowych z Atom XML."

# Utwórz folder _data, jeśli nie istnieje
FileUtils.mkdir_p(DATA_DIR)
output_path = File.join(DATA_DIR, OUTPUT_FILE)

begin
  # Pobierz i sparsuj XML
  xml_data = URI.open(XML_URL).read
  doc = Nokogiri::XML(xml_data)
  doc.remove_namespaces!  # usuwa 'g:' i inne przestrzenie nazw

  products = []

  doc.xpath('//entry').each do |entry|
    product_data = {}

    fields_to_extract = [
      'id', 'title', 'link', 'image_link', 'description',
      'price', 'sale_price', 'availability', 'brand'
    ]

    fields_to_extract.each do |field_name|
      element = entry.at_xpath(field_name)
      next unless element && element.text

      value = element.text.strip

      # Przekształć cenę do formatu "30.00"
      if ['price', 'sale_price'].include?(field_name)
        numeric = value.gsub(/[^\d.,]/, '').tr(',', '.').to_f
        value = format('%.2f', numeric)
      end

      product_data[field_name] = value
    end

    # Dodaj produkt tylko jeśli ma ID i tytuł
    if product_data['id'] && product_data['title']
      products << product_data
    end
  end

  # Zapisz dane do pliku JSON
  File.open(output_path, 'w') do |f|
    f.write(JSON.pretty_generate(products))
  end

  puts "SUKCES: Zapisano #{products.length} produktów do pliku #{output_path}"

rescue StandardError => e
  puts "BŁĄD: Wystąpił problem: #{e.message}"
  puts e.backtrace
  exit 1
end