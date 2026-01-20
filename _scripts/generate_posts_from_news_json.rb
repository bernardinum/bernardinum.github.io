#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require 'dotenv/load'

DATA_PATH = File.expand_path('../_data/news.json', __dir__)
POSTS_DIR = File.expand_path('../_posts', __dir__)
PREFIX    = 'shoper-news-'
DEBUG     = (ENV['BERNARDINUM_DEBUG'].to_s.strip == '1')

def log_info(msg)
  puts "INFO: #{msg}"
end

def log_warn(msg)
  warn "WARN: #{msg}"
end

def sanitize_string(val)
  return val unless val.is_a?(String)
  s = val.dup
  s = s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  s = s.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/, '')
  s = s.gsub(/[\u007F-\u009F\u0085\u2028\u2029]/, '')
  s
end

def slugify(str)
  s = sanitize_string(str.to_s)

  map = {
    'ą'=>'a','ć'=>'c','ę'=>'e','ł'=>'l','ń'=>'n','ó'=>'o','ś'=>'s','ż'=>'z','ź'=>'z',
    'Ą'=>'a','Ć'=>'c','Ę'=>'e','Ł'=>'l','Ń'=>'n','Ó'=>'o','Ś'=>'s','Ż'=>'z','Ź'=>'z'
  }
  s = s.chars.map { |ch| map.key?(ch) ? map[ch] : ch }.join

  s = s.downcase
  s = s.gsub(/&[a-z]+;/i, '')
  s = s.gsub(/[^a-z0-9]+/, '-')
  s = s.gsub(/\A-+|-+\z/, '')
  s = 'post' if s.empty?
  s
end

def parse_time(str)
  s = str.to_s.strip
  return Time.now.utc if s.empty?

  # jeśli brak strefy, traktuj jako UTC (bezpieczne dla GH runner)
  if s =~ /(\+|\-)\d{2}:\d{2}\z/ || s.end_with?('Z')
    Time.parse(s)
  else
    Time.parse(s + ' UTC')
  end
rescue
  Time.now.utc
end

def remove_first_img(html)
  return '' if html.nil?
  html.to_s.sub(/<img\b[^>]*>\s*/i, '')
end

def strip_data_attributes(html)
  return '' if html.nil?
  html.to_s.gsub(/\sdata-[a-z0-9_\-:]+=(["']).*?\1/i, '')
end

def normalize_whitespace(html)
  return '' if html.nil?
  s = html.to_s
  s = s.gsub("\r\n", "\n")
  s = s.gsub("\r", "\n")
  s
end

def build_front_matter(title, date, shoper_id, image_url)
  fm = []
  fm << "---"
  # FIX: poprawny layout bez backslasha
  fm << "layout: posts/post-boxed"
  fm << "title: #{title.to_s.inspect}"
  fm << "date: #{date.strftime('%Y-%m-%d %H:%M:%S %z')}"
  fm << "shoper_id: #{shoper_id}"
  fm << "slug: #{slugify(title)}-#{shoper_id}"
  if image_url && !image_url.to_s.strip.empty?
    fm << "post_image: #{image_url.to_s.inspect}"
  end
  fm << "categories: [Aktualności]"
  fm << "---"
  fm.join("\n") + "\n"
end

def load_news(path)
  raise "Brak pliku: #{path}" unless File.exist?(path)
  JSON.parse(File.read(path, mode: 'rb'))
end

def desired_post_paths(latest, posts_dir)
  latest.map do |item|
    t = parse_time(item['date'])
    date_for_filename = t.strftime('%Y-%m-%d')
    title = item['title'].to_s
    id = item['id'].to_i
    filename = "#{date_for_filename}-#{PREFIX}#{slugify(title)}-#{id}.md"
    File.join(posts_dir, filename)
  end
end

def cleanup_old_generated(posts_dir, desired_paths)
  Dir.glob(File.join(posts_dir, "*-#{PREFIX}*.md")).each do |path|
    next if desired_paths.include?(path)
    File.delete(path)
  end
end

def write_post(path, fm, body)
  File.open(path, 'wb') do |f|
    f.write(fm.encode('UTF-8'))
    f.write(body.encode('UTF-8'))
    f.write("\n")
  end
end

# --- MAIN ---
FileUtils.mkdir_p(POSTS_DIR)

news = load_news(DATA_PATH)
news = news.select { |x| x.is_a?(Hash) }

latest = news.sort_by { |x| x['id'].to_i }.reverse.first(30)

desired = desired_post_paths(latest, POSTS_DIR)
cleanup_old_generated(POSTS_DIR, desired)

latest.each_with_index do |item, idx|
  id = item['id'].to_i
  title = sanitize_string(item['title'].to_s)
  date = parse_time(item['date'])
  image_url = sanitize_string(item['image_url'].to_s)

  content = sanitize_string(item['content'].to_s)
  content = normalize_whitespace(content)
  content = strip_data_attributes(content)
  content = remove_first_img(content)

  fm = build_front_matter(title, date, id, image_url)
  post_path = desired[idx]
  write_post(post_path, fm, content)
end

log_info("Wygenerowano/odświeżono #{latest.length} postów w #{POSTS_DIR}")
