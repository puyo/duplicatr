require 'rubygems' rescue nil
require 'bundler/setup'
require 'flickraw'
require 'pp'
require 'yaml'
require 'pathname'
require 'set'

DuplicatrConfig = YAML.load_file('duplicatr.yml')

FlickRaw.api_key = DuplicatrConfig['api_key']
FlickRaw.shared_secret = DuplicatrConfig['shared_secret']
flickr.access_token = DuplicatrConfig['access_token']
flickr.access_secret = DuplicatrConfig['access_secret']

photos_yml = Pathname.new('photos.yml')

if not photos_yml.exist?
  user = flickr.people.findByUsername(:username => 'blue_puyo')
  page = 1
  all = []
  loop do
    puts "Fetching page #{page}..."
    photos = flickr.photos.search(:user_id => user['nsid'], :per_page => 500, :page => page)
    break if photos.size == 0
    all.push(*photos)
    page += 1
  end

  photos_yml.open('w') do |f|
    f.write(all.to_yaml)
  end

  puts "Dumping photo index..."
end

puts "Loading photo index..."
photos = YAML.load_file(photos_yml)
puts "#{photos.size} total entries"

dupes = Hash.new{|h,k| h[k] = Set.new }
seen = {}
photos.each do |photo|
  title = photo['title']
  if !title.nil? and title != ''
    if seen[title]
      dupes[title] << seen[title] << photo
    end
    seen[title] = photo
  end
end

puts "#{dupes.size} potential dupes (by title)"
dupe = dupes['Anna']
pp dupe
dupe.each do |photo|
  pp flickr.photos.getSizes(:photo_id => photo['id'])
end
#pp dupes
