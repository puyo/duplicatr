require 'bundler/setup'
require 'flickraw'
require 'pp'
require 'yaml'
require 'pathname'
require 'set'
require 'time'
require 'typhoeus'

def dash_case(str)
  str.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    gsub(/\s/, '-').
    tr('_', '-').
    downcase
end

class ByeFlickr
  def initialize
    @config = YAML.load_file('duplicatr.yml')
    FlickRaw.api_key = @config['api_key']
    FlickRaw.shared_secret = @config['shared_secret']
    flickr.access_token = @config['access_token']
    flickr.access_secret = @config['access_secret']
  end

  def username
    config['username']
  end

  def user
    @user ||= flickr.people.findByUsername(username: @username)
  end

  def authenticate
    if flickr.access_token.nil? || flickr.access_secret.nil?
      token = flickr.get_request_token
      auth_url = flickr.get_authorize_url(token['oauth_token'], perms: 'read')

      puts "Open this url in your browser to complete the authentication process : #{auth_url}"
      puts "Copy here the number given when you complete the process."
      verify = gets.strip

      begin
        flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
        login = flickr.test.login
        puts "You are now authenticated as #{login.username} with token #{flickr.access_token} and secret #{flickr.access_secret}"
      rescue FlickRaw::FailedResponse => e
        puts "Authentication failed : #{e.msg}"
      end
    end
  end

  def fetch_index
    user_id = @config['user_id'] || user['nsid']
    page = 1
    loop do
      begin
        index_path = Pathname.new(format("index/%05d.yml", page))
        if !index_path.exist?
          puts "Fetching #{index_path}..."
          index_path.dirname.mkpath
          per_page = 500
          photos = flickr.photos.search(user_id: user_id, per_page: per_page, page: page)
          photos = photos.map{ |photo| photo.marshal_dump.first }
          # check it's not identical to the last one...
          begin
            previous_list = YAML.load_file(Pathname.new(format("index/%05d.yml", page - 1)))
            if previous_list == photos
              break # done!
            end
          rescue
            # OK
          end
          index_path.open('w') { |f| f.write(photos.to_yaml) }
          if photos.size < per_page
            break # done!
          end
        end
        page += 1
      end
    end
  end

  def fetch_photos
    Pathname.glob(Pathname.new('index/*.yml')) do |index_path|
      photos = YAML.load_file(index_path)
      photos.each do |photo|
        title = photo['title']
        id = photo['id']
        #pp flickr.photos.getSizes(photo_id: photo['id'])
        info = flickr.photos.getInfo(photo_id: id)
        timestamp = Time.parse(info['dates']['taken'])
        o_url = FlickRaw.url_o(info)
        slug = dash_case(title)
        if slug.size > 0
          slug = '_' + slug.tr('_', '-')
        end
        ext = File.extname(o_url)
        download_path = Pathname.new(timestamp.strftime("downloads/%Y/%m-%d_#{id}#{slug}#{ext}"))
        fetch(url: o_url, path: download_path)
      end
    end
  end

  def fetch(url:, path:)
    if path.exist?
      puts "Skipping #{path} as it already exists..."
      return
    end
    puts path
    dl_path = Pathname.new('.download')
    dl_path.open('wb') do |file|
      request = Typhoeus::Request.new(url)
      request.on_headers do |response|
        if response.code != 200
          raise 'Request failed'
        end
      end
      request.on_body do |chunk|
        file.write(chunk)
        sleep 0.05
      end
      request.on_complete do |response|
        file.close
      end
      request.run
    end
    path.dirname.mkpath
    dl_path.rename(path)
  end
end

if __FILE__ == $0
  b = ByeFlickr.new
  b.authenticate
  b.fetch_index
  b.fetch_photos
end
