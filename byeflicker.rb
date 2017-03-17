require 'bundler/setup'
require 'flickraw'
require 'pp'
require 'yaml'
require 'pathname'
require 'set'
require 'time'

module ByeFlickr
  Config = YAML.load_file('duplicatr.yml')

  def self.setup
    FlickRaw.api_key = Config['api_key']
    FlickRaw.shared_secret = Config['shared_secret']
    flickr.access_token = Config['access_token']
    flickr.access_secret = Config['access_secret']
    @username = Config['username']
  end

  def self.photos_yml
    Pathname.new('photos.yml')
  end

  def self.user
    @user ||= flickr.people.findByUsername(username: @username)
  end

  def self.fetch_photos_yml
    page = 1
    all = []
    loop do
      puts "Fetching page #{page}..."
      photos = flickr.photos.search(user_id: user['nsid'], per_page: 500, page: page, tags: 'art')
      break if photos.empty?
      all.push(*photos)
      page += 1
    end
    puts "Dumping photo index..."
    photos_yml.open('w') do |f|
      f.write(all.to_yaml)
    end
  end

  pp flickr.photos.getSizes(photo_id: photo['id'])

  def self.fetch_file(uri, filename)
    File.open(filename, 'w') do |f|
      uri = URI.parse(url)
      Net::HTTP.start(uri.host, uri.port) do |http|
        http.request_get(uri.path) do |res|
          res.read_body do |seg|
            f << seg
            sleep 0.005
          end
        end
      end
    end
  end

  def self.fetch_all
    photos = YAML.load_file(photos_yml)
    photos.each do |photo|
      title = photo['title']
      info = flickr.photos.getInfo(photo_id: photo['id'])
      timestamp = Time.parse(info['dates']['taken'])
      o_url = FlickRaw.url_o(info)
      slug = title.downcase.gsub(/[^0-9A-Za-z]+/, ' ').strip.gsub(' ', '-')
      ext = File.extname(o_url)
      download_path = timestamp.strftime("downloads/%Y-%m-%d_#{slug}#{ext}")
      if !Pathname(download_path).exist?
        puts title

        system('curl', '-s', '-o', download_path, o_url)
      else
        puts "Skipping #{title}..."
      end
    end
  end
end

if __FILE__ == $0
  ByeFlickr.setup
  ByeFlickr.fetch_photos_yml
  ByeFlickr.fetch_all
end
