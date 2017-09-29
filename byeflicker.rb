require 'bundler/setup'
require 'flickraw'
require 'pp'
require 'yaml'
require 'pathname'
require 'set'
require 'time'
require 'uri'

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
          photos = flickr.photos.search(user_id: user_id, per_page: per_page, page: page, extras: 'media,original_format,date_taken,url_o,original_format,path_alias')
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
    all_photos = []
    Pathname.glob(Pathname.new('index/*.yml')) do |index_path|
      photos = YAML.load_file(index_path)
      all_photos.push(*photos)
    end
    total = all_photos.size
    all_photos.each_with_index do |photo, i|
      title = photo['title']
      id = photo['id']
      timestamp = Time.parse(photo['datetaken'])
      o_url = photo['url_o']
      slug = dash_case(title)
      if slug.size > 0
        slug = '_' + slug.tr('_', '-')
      end

      percent = i * 100 / total
      print format("%3d%% ", percent)

      prefix = timestamp.strftime("downloads/%Y/%m-%d_#{id}#{slug}")

      if photo['media'] == 'video'
        jpg = Pathname.new(prefix + '.jpg')
        jpg.delete if jpg.exist?
      end

      existing_paths = Dir.glob(prefix + '.*')
      if existing_paths.any?
        puts "EXISTS      #{existing_paths.first}"
        next
      end

      if photo['media'] == 'video'
        o_url = fetch_video_o_url(id: id)
      end

      begin
        ext = File.extname(URI(o_url).path)
        download_path = Pathname.new(prefix + ext)
        puts "DOWNLOADING #{download_path}"
        fetch(url: o_url, path: download_path)
      rescue ArgumentError => e
        puts "FAILURE     #{prefix}"
        File.open("fail.log", "a") do |f|
          f.puts e.to_s
          f.puts photo.inspect
          f.puts
        end
      end
    end
  end

  def fetch(url:, path:)
    dl_path = Pathname.new('.download')
    begin
      5.times do
        system('curl', '--silent', '--limit-rate', '500K', '--output', dl_path.to_s, url)
        type = `file #{dl_path}`
        if type.match(/html/)
          $stderr.puts "Failed to download, got HTML"
          $stderr.puts File.read(dl_path)
          sleep 5
        else
          break
        end
      end
    end
    path.dirname.mkpath
    dl_path.rename(path)
  end

  # Requires you to log into Flickr and then copy the cookie out of your web
  # browser into the YML file
  def fetch_video_o_url(id:)
    require 'typhoeus'
    auth_url = 'https://www.flickr.com/video_download.gne?id=' + id
    dl_url = nil
    request = Typhoeus::Request.new(auth_url, headers: {Cookie: @config['cookie']})
    request.on_complete do |response|
      dl_url = response.headers['location']
    end
    request.run
    return dl_url
  end
end

if __FILE__ == $0
  b = ByeFlickr.new
  b.authenticate
  b.fetch_index
  b.fetch_photos
end
