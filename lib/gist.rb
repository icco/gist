require 'open-uri'
require 'net/http'
require 'optparse'

require 'gist/manpage' unless defined?(Gist::Manpage)
require 'gist/version' unless defined?(Gist::Version)

# You can use this class from other scripts with the greatest of
# ease.
#
#   >> Gist.read(gist_id)
#   Returns the body of gist_id as a string.
#
#   >> Gist.write(content)
#   Creates a gist from the string `content`. Returns the URL of the
#   new gist.
#
#   >> Gist.copy(string)
#   Copies string to the clipboard.
#
#   >> Gist.browse(url)
#   Opens URL in your default browser.
module Gist
  extend self

  GIST_URL   = 'http://gist.github.com/%s.txt'
  CREATE_URL = 'http://gist.github.com/gists'

  PROXY = ENV['HTTP_PROXY'] ? URI(ENV['HTTP_PROXY']) : nil
  PROXY_HOST = PROXY ? PROXY.host : nil
  PROXY_PORT = PROXY ? PROXY.port : nil

  TEMP_FILE = '.tmp_gists'
  @@files = []

  # Parses command line arguments and does what needs to be done.
  def execute(*args)
    private_gist = false
    gist_extension = nil

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: gist [options] [filenames or stdin]"

      opts.on('-p', '--private', 'Make the gist private') do
        private_gist = true
      end

      t_desc = 'Set syntax highlighting of the Gist by file extension'
      opts.on('-t', '--type [EXTENSION]', t_desc) do |extension|
        gist_extension = '.' + extension
      end

      opts.on('-m', '--man', 'Print manual') do
        Gist::Manpage.display("gist")
      end

      opts.on('-h', '--help', 'Display this screen') do
        puts opts
        exit
      end
    end

    opts.parse!(args)

    begin
      if $stdin.tty?
        # Run without stdin.

        # No args, print help.
        if args.empty?
          puts opts
          exit
        end

        # Check if arg is a file. If so, grab the content.
        if File.exists?(file = args[0])
          input = File.read(file)
          gist_extension = File.extname(file) if file.include?('.')
        else
          abort "Can't find #{file}"
        end
      else
        # Read from standard input.
        input = $stdin.read
      end

      url = write(input, private_gist, gist_extension)
      browse(url)
      puts copy(url)
    rescue => e
      warn e
      puts opts
    end
  end

  # Create a gist on gist.github.com
  def write(content, private_gist = false, gist_extension = nil)
    url = URI.parse(CREATE_URL)

    # Net::HTTP::Proxy returns Net::HTTP if PROXY_HOST is nil
    proxy = Net::HTTP::Proxy(PROXY_HOST, PROXY_PORT)
    req = proxy.post_form(url, data(nil, gist_extension, content, private_gist))

    req['Location']
  end

  # Given a gist id, returns its content.
  def read(gist_id)
    open(GIST_URL % gist_id).read
  end

  # Adds a file to the file array to be sent
  def add_file(name, content)
    load_files
    @@files << {:name => name, :content => content}
    save_files
  end

  # List files waiting to be sent
  def list_files
     load_files
     ret = []
     @@files.each do|a|
        ret << a[:name]
     end

     return ret
  end
  
  # Given a url, tries to open it in your browser.
  # TODO: Linux, Windows
  def browse(url)
    if RUBY_PLATFORM =~ /darwin/
      `open #{url}`
    end
  end

  # Tries to copy passed content to the clipboard.
  def copy(content)
    cmd = case true
    when system("which pbcopy > /dev/null")
      :pbcopy
    when system("which xclip > /dev/null")
      :xclip
    when system("which putclip")
      :putclip
    end

    if cmd
      IO.popen(cmd.to_s, 'r+') { |clip| clip.print content }
    end

    content
  end

private
  # Give a file name, extension, content, and private boolean, returns
  # an appropriate payload for POSTing to gist.github.com
  def data(name, ext, content, private_gist, number)
    number = number ? 1 : number 
    return {
      "file_ext[gistfile#{number}]"      => ext,
      "file_name[gistfile#{number}]"     => name,
      "file_contents[gistfile#{number}]" => content
    }.merge(private_gist ? { 'action_button' => 'private' } : {}).merge(auth)
  end

  def data_files(private_gist)
    params = {}
    @@files.each_with_index do |file, i|
      params.merge!(data(file[:name], nil, file[:content], private_gist, (i+1)))
    end
  end

  # Returns a hash of the user's GitHub credentials if see.
  # http://github.com/guides/local-github-config
  def auth
    user  = `git config --global github.user`.strip
    token = `git config --global github.token`.strip

    user.empty? ? {} : { :login => user, :token => token }
  end

  # Pulls file data out of the temp file
  def load_files
    path = File.join(File.dirname(__FILE__), TEMP_FILE)
    save_files unless File.exists?(path)
    @@files = Marshal.load(File.read(path))
    @@files ||= []
  end
  
  # Merges all files into a temp file
  def save_files
    path = File.join(File.dirname(__FILE__), TEMP_FILE)
    File.open(path, 'w') {|f| f.puts Marshal.dump(@@files) }
  end
end
