require 'mechanize'
require 'logger'
require 'pry'
require 'zip/zip'

class GetOkayPants
  attr_accessor :agent, :first_page, :chapter_markers, :range, :previous_url

  def initialize(range)
    @agent = Mechanize.new
    @agent.log = Logger.new "mech.log"
    @agent.user_agent_alias = 'Mac Safari'
    @agent.follow_meta_refresh = false
    @agent.redirect_ok = false
    @range = range
  end

  def prep_chapters
    # Prep Chapter Markers
    page = agent.get("http://web.archive.org/web/20070703080037/http://www.okaypants.com/comic.php")
    @chapter_markers = {}
    i = 1
    @first_page = 0
    load_chapter = 1
    if @range && @range.is_a?(Array)
      load_chapter = @range.first
    end
    page.search('//option').reverse.each{ |option|
      if option.attributes["value"]
        marker = option.attributes["value"].to_s.split('comic.php?st=')[-1].to_s
        @first_page = marker if i == load_chapter
        @chapter_markers[marker] = {chapter_id: i, chapter_name: option.text}
        i = i + 1
      end
    }
  end

  def start_download
    cbz_dir = "okpants_comics"
    if File.directory?(cbz_dir)
      FileUtils.mv cbz_dir, Time.now.to_i.to_s + "_" + cbz_dir
    end
    raw_dir = "saved_comics"
    if File.directory?(raw_dir)
      FileUtils.mv raw_dir, Time.now.to_i.to_s + "_" + raw_dir
    end
    # if File.directory?("okpants_comics")
    #   FileUtils.rm_rf("okpants_comics")
    # end
    # if File.directory?("saved_comics")
    #   FileUtils.rm_rf("saved_comics")
    # end
    # Start with first page of first Chapter
    url = "http://web.archive.org/web/20071008120752/http://www.okaypants.com/comic.php?st="
    page = @agent.get("#{url}#{@first_page}")
    puts @agent.current_page().uri()

    keep_going = true
    current_chapter = {}
    page_cursor = 1
    while keep_going
      page = @agent.current_page()
      current_page_id = page.uri().to_s.split("http://www.okaypants.com/comic.php?st=")[-1]
      chapter_start = @chapter_markers[current_page_id]
      if chapter_start
        zip_previous_chapter(current_chapter[:chapter_id]) if current_chapter[:chapter_id]
        current_chapter = chapter_start
        puts "Chapter switched to -> " + current_chapter[:chapter_id].to_s
        if @range && @range.is_a?(Array)
          if current_chapter[:chapter_id] > @range.last
            keep_going = false
            exit
          end
        end
      end
      comic_image = page.search("//img[contains(@src,'comic')]").first.attributes["src"].to_s
      comic_url = "http://web.archive.org#{comic_image}"
      image_name = comic_image.split('/')[-1]
      begin
        comic_redirect_page = @agent.get(comic_url)
        if comic_redirect_page.code == "302"
          comic_url = "http://web.archive.org#{comic_redirect_page.header['location']}"
          @agent.get("#{comic_url}").save("#{chapter_directory(current_chapter[:chapter_id])}/#{page_cursor}_#{image_name}")
        end
      rescue Net::HTTPNotFound => e
      rescue Net::HTTPServiceUnavailable, Mechanize::ResponseCodeError => e
        retry_count += 1
        unless retry_count > 3
          sleep(3)
          retry
        end
      end
      puts "Currently Downloading: #{current_chapter[:chapter_name]}"
      puts "Downloading comic address: #{comic_url}"

      next_link = page.link_with(:text => "Next")
      if next_link
        next_url = "http://web.archive.org#{next_link.href}"
        goto_redirected_url(next_url, url)
      else
        zip_previous_chapter(current_chapter[:chapter_id])
        keep_going = false
      end
      page_cursor = page_cursor + 1
      sleep(1)
    end
  end

  def goto_redirected_url(next_url, base_url)
    comic_id = next_url.split("http://www.okaypants.com/comic.php?st=")[-1].to_i
    next_url = "#{base_url}050122" if comic_id == 50118
    if @previous_url == next_url
      comic_id = comic_id + 1
      next_url = "#{base_url}0#{comic_id.to_s}"
    end
    begin
      next_page = @agent.get(next_url)
    rescue Mechanize::ResponseCodeError, Net::HTTPServiceUnavailable => e
      retry_count += 1
      unless retry_count > 3
        sleep(3)
        retry
      end
    end
    if next_page.code == "302"
      new_url = "http://web.archive.org#{next_page.header['location']}"
      begin
        @agent.get new_url
      rescue Mechanize::ResponseCodeError, Net::HTTPServiceUnavailable => e
        retry_count += 1
        unless retry_count > 3
          sleep(3)
          retry
        end
      end
      @previous_url = new_url
    end
  end

  def chapter_directory(chapter_id)
    "okpants_comics/chapter_#{chapter_id}"
  end

  def zip_file_path(chapter_id)
    directory_name = "saved_comics"
    unless File.directory?(directory_name)
      FileUtils.mkdir_p(directory_name)
    end
    "#{directory_name}/chapter_#{chapter_id}.cbz"
  end

  def zip_previous_chapter(chapter_id)
    directory = chapter_directory(chapter_id)
    zipfile_name = zip_file_path(chapter_id)
    if File.exist?(zipfile_name)
      File.delete(zipfile_name)
    end
    Zip::ZipFile.open(zipfile_name, 'w') do |zipfile|
      Dir["#{directory}/**/**"].reject{|f|f==zipfile_name}.each do |file|
        zipfile.add(file.sub(directory+'/',''),file)
      end
    end
  end

  class << self
    def new_download(range = nil)
      scary_downloader = self.new(range)
      scary_downloader.prep_chapters
      scary_downloader.start_download
    end
  end

end

GetOkayPants.new_download(nil)

exit
