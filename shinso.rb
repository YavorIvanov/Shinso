class Shinso
  
  # ——— NOTES ————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
  # Shinso is a tool that will vampire content by crawling,
  # parsing and making smart decisions about the page content.
  # ———
  # Copyright (C) 2012 Yavor Ivanov <yavor.ivanov@icloud.com>
  # Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
  # The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  # ——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
  
  #require "mechanize"
  require "open-uri"
  require "zlib"
  require "nokogiri"
  require "sanitize"
  require "htmlentities"
  require "readability"
  require "charguess"
  require "rest-client"
  
  attr_accessor :errors,            # <= collect all the errors
                :url_posted,        # <= user submited link
                :url_parsed,        # <= the link after possible redirects
                :url_host,          # <= the true host
                :status,            # <= header response ... page status 200, 404
                :content_type,      # <= how the page was served as ... like text/html
                :content_encoding,  # <= how the page was served as ... like gzip
                :charset,           # <= character encoding like utf8 and so one
                :charset_guess,     # <= character encoding like utf8 and so one
                :content,           # <= Nokogiri obj - source code of the page (should have been normalized in various ways)
                :page_title,        # <= a hash of possible data
                :page_summary,      # <= a hash of possible data
                :page_photo,        # <= a hash of possible data
                :page_keywords      # <= a hash of possible data
  
  SHINSO_HEADERS = {
    'Accept'          => '*/*',
    'Accept-Charset'  => 'utf-8, windows-1251;q=0.7, *;q=0.6',
    'Accept-Encoding' => 'gzip,deflate',
    'Accept-Language' => 'bg-BG, bg;q=0.8, en;q=0.7, *;q=0.6',
    'Connection'      => 'keep-alive',
    'Cookie'          => '',
    'From'            => '',
    'Referer'         => '',
    'User-Agent'      => 'Mozilla/5.0 (compatible; Shinso/3.0)'
  }
  
  def crawl(url_address)
    self.errors = Array.new
    begin
      begin
        url_address = URI.parse(url_address)
      rescue URI::InvalidURIError
        url_address = URI.decode(url_address)
        url_address = URI.encode(url_address)
        url_address = URI.parse(url_address)
      end
      url_address.normalize!
      stream = ""
      timeout(10) { stream = url_address.open(SHINSO_HEADERS) }
      if stream.size > 0
        url_crawled = URI.parse(stream.base_uri.to_s)
      else
        self.errors << "Сайта е достъпен, но няма съдържание."
        return
      end
    rescue Errno::ECONNREFUSED
      self.errors << "Сайта не може да бъде достъпен - Errno::ECONNREFUSED"
      return
    rescue Exception => exception
      self.errors << exception
      return
    end
    # extract information before html parsing
    self.url_posted       = url_address.to_s
    self.url_parsed       = url_crawled.to_s
    self.url_host         = url_crawled.host
    self.status           = stream.status
    self.content_type     = stream.content_type
    self.content_encoding = stream.content_encoding
    self.charset          = stream.charset
    if    stream.content_encoding.include?('gzip')
      document = Zlib::GzipReader.new(stream).read
    elsif stream.content_encoding.include?('deflate')
      document = Zlib::Deflate.new().deflate(stream).read
    #elsif stream.content_encoding.include?('x-gzip') or
    #elsif stream.content_encoding.include?('compress')
    else
      document = stream.read
    end
    self.charset_guess = CharGuess.guess(document)
    begin
      if not self.charset_guess.blank? and (not self.charset_guess.downcase == 'utf-8' or not self.charset_guess.downcase == 'utf8')
        if self.charset == 'windows-1251' and self.charset_guess.downcase == 'koi8-r'
          document = Iconv.iconv("UTF-8", self.charset, document).to_s
        else
          document = Iconv.iconv("UTF-8", self.charset_guess, document).to_s
        end
      end
    rescue Iconv::IllegalSequence
      document = document.to_s
    end
    document = Nokogiri::HTML.parse(document,nil,"utf8")
    document.xpath('//script').remove
    document.xpath('//SCRIPT').remove
    for item in document.xpath('//*[translate(@src, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")]')
      item.set_attribute('src',make_absolute_address(item['src']))
    end
    document = document.to_s.gsub(/<!--(.|\s)*?-->/,'')
    self.content = Nokogiri::HTML.parse(document,nil,"utf8")
  end
  
  def parse()
    # === Title ===
    self.page_title                         = Hash.new
    begin
      timeout(1) do
        title                               = self.content.xpath('//title')
        self.page_title[:title]             = normalize(title.text) if not title.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//meta[translate(@name,     "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "title"][@content]')
        self.page_title[:meta_title]        = normalize(title.first['content']) if not title.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//meta[translate(@property, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "og:title"][@content]')
        self.page_title[:og_title]          = normalize(title.first['content']) if not title.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//*[translate(@itemprop,    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "name"]')
        self.page_title[:itemprop_name]     = normalize(title.text)              if not title.blank? and not title.text.blank?
        self.page_title[:itemprop_name]     = normalize(title.first['content'])  if not title.blank? and not title.first['content'].blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//*[translate(@itemprop,    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "headline"]')
        self.page_title[:itemprop_headline] = normalize(title.text)              if not title.blank? and not title.text.blank?
        self.page_title[:itemprop_headline] = normalize(title.first['content'])  if not title.blank? and not title.first['content'].blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//following::h1[1]')
        self.page_title[:content_h1_f]      = normalize(title.text)       if not title.blank?
        self.page_title[:content_h1_f]      = normalize(title.first.text) if not title.blank? and not title.first.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//following::h1[2]')
        self.page_title[:content_h1_s]      = normalize(title.text)       if not title.blank?
        self.page_title[:content_h1_s]      = normalize(title.first.text) if not title.blank? and not title.first.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        title                               = self.content.xpath('//following::h2[1]')
        self.page_title[:content_h2_f]      = normalize(title.text)       if not title.blank?
        self.page_title[:content_h2_f]      = normalize(title.first.text) if not title.blank? and not title.first.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    # === Summary ===
    self.page_summary                             = Hash.new
    begin
      timeout(1) do
        summary                                   = self.content.xpath('//meta[translate(@name,     "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "description"][@content]')
        self.page_summary[:meta_description]      = normalize(summary.first['content']) if not summary.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        summary                                   = self.content.xpath('//meta[translate(@property, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "og:description"][@content]')
        self.page_summary[:og_description]        = normalize(summary.first['content']) if not summary.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        summary                                   = Readability::Document.new(self.content.to_s, :remove_empty_nodes => true).content
        summary                                   = normalize(Sanitize.clean(summary).gsub('  ',' ')) if not summary.blank?
        summary                                   = nil if not summary.blank? and summary.mb_chars.size < 2
        self.page_summary[:readability]           = summary if not summary.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        summary                                   = self.content.xpath('//*[translate(@itemprop, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "articlebody"]')
        self.page_summary[:itemprop_articlebody]  = normalize(summary.text) if not summary.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        summary                                   = self.content.xpath('//*[translate(@itemprop, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "description"]')
        self.page_summary[:itemprop_description]  = normalize(summary.text)              if not summary.blank? and not summary.blank?
        self.page_summary[:itemprop_description]  = normalize(summary.first['content'])  if not summary.blank? and not summary.first['content'].blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    # === Photo ===
    self.page_photo                     = Hash.new
    begin
      timeout(1) do
        photo                               = self.content.xpath('//meta[translate(@property, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "og:image"][@content]')
        self.page_photo[:og_image]          = photo.first['content'] if not photo.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        photo                               = self.content.xpath('//link[translate(@rel,      "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "image_src"][@href]')
        self.page_photo[:link_rel_image]    = photo.first['href'] if not photo.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        photo                               = self.content.xpath('//img[translate(@itemprop,  "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "image"][@src]')
        self.page_photo[:itemprop_image]    = photo.first['src'] if not photo.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    #photo                               = Readability::Document.new(self.content.to_s, :min_image_width => 140, :min_image_height => 140).images
    #self.page_photo[:readability]       = photo[0] if not photo.blank? and photo.class == Array
    begin
      timeout(1) do
        photo                               = self.content.xpath('(//h1/following::img[@width > 140 or substring-before(@width, "px") > 140 or @height > 140 or substring-before(@height, "px") > 140]/@src)[1]')
        self.page_photo[:assumed_after_h1]  = photo.text if not photo.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        photo                               = self.content.xpath('(//h2/following::img[@width > 140 or substring-before(@width, "px") > 140 or @height > 140 or substring-before(@height, "px") > 140]/@src)[1]')
        self.page_photo[:assumed_after_h2]  = photo.text if not photo.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    # === Keywords ===
    self.page_keywords                      = Hash.new
    begin
      timeout(1) do
        keywords                                = self.content.xpath('//meta[translate(@name,     "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "keywords"][@content]')
        self.page_keywords[:meta_keywords]      = normalize(keywords.first['content']) if not keywords.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        keywords                                = self.content.xpath('//meta[translate(@name,     "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "tags"][@content]')
        self.page_keywords[:meta_tags]          = normalize(keywords.first['content']) if not keywords.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        keywords                                = self.content.xpath('//*[translate(@itemprop, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "keywords"]')
        self.page_keywords[:itemprop_keywords]  = normalize(keywords.text)              if not keywords.blank? and not keywords.blank?
        self.page_keywords[:itemprop_keywords]  = normalize(keywords.first['content'])  if not keywords.blank? and not keywords.first['content'].blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        keywords                                = self.content.xpath('//a[translate(@rel,  "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz") = "tag"]')
        self.page_keywords[:rel_tag]            = normalize(keywords.collect{|x| x.text}.join(',')) if not keywords.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
    begin
      timeout(1) do
        keywords                                = self.content.xpath('//*[(
                                                                            contains(
                                                                              translate(@class, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"),"tags"
                                                                            ) or
                                                                            contains(
                                                                              translate(@id,    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"),"tags"
                                                                            )
                                                                          ) and not (
                                                                            contains(
                                                                              translate(@class, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"),"content"
                                                                            ) or
                                                                            contains(
                                                                              translate(@id,    "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"),"content"
                                                                            )
                                                                          )]//a')
        self.page_keywords[:assumed_tags]       = normalize(keywords.collect{|x| x.text}.join(',')) if not keywords.blank?
      end
    rescue Timeout::Error => err
      puts err # ignore it it's not worth it
    end
  end
  
  def decision()
    timeout(15) do
      # best title
      if    not self.page_title[:content_h1_f].blank? and
            not self.page_title[:title].blank? and
                self.page_title[:title].match(Regexp.escape(self.page_title[:content_h1_f])) and
                self.page_title[:title].mb_chars.size - self.page_title[:content_h1_f].mb_chars.size < self.page_title[:content_h1_f].mb_chars.size
        serve = self.page_title[:content_h1_f]
      elsif not self.page_title[:content_h1_s].blank? and
            not self.page_title[:title].blank? and
                self.page_title[:title].match(Regexp.escape(self.page_title[:content_h1_s])) and
                self.page_title[:title].mb_chars.size - self.page_title[:content_h1_s].mb_chars.size < self.page_title[:content_h1_s].mb_chars.size
        serve = self.page_title[:content_h1_s]
      elsif not self.page_title[:content_h2_f].blank? and
            not self.page_title[:title].blank? and
                self.page_title[:title].match(Regexp.escape(self.page_title[:content_h2_f])) and
                self.page_title[:title].mb_chars.size - self.page_title[:content_h2_f].mb_chars.size < self.page_title[:content_h2_f].mb_chars.size
        serve = self.page_title[:content_h2_f]
      elsif not self.page_title[:content_h1_f].blank? and
            not self.page_title[:og_title].blank? and
                self.page_title[:og_title].match(Regexp.escape(self.page_title[:content_h1_f])) and
                self.page_title[:og_title].mb_chars.size - self.page_title[:content_h1_f].mb_chars.size < self.page_title[:content_h1_f].mb_chars.size
        serve = self.page_title[:content_h1_f]
      elsif not self.page_title[:content_h1_s].blank? and
            not self.page_title[:og_title].blank? and
                self.page_title[:og_title].match(Regexp.escape(self.page_title[:content_h1_s])) and
                self.page_title[:og_title].mb_chars.size - self.page_title[:content_h1_s].mb_chars.size < self.page_title[:content_h1_s].mb_chars.size
        serve = self.page_title[:content_h1_s]
      elsif not self.page_title[:content_h2_f].blank? and
            not self.page_title[:og_title].blank? and
                self.page_title[:og_title].match(Regexp.escape(self.page_title[:content_h2_f])) and
                self.page_title[:og_title].mb_chars.size - self.page_title[:content_h2_f].mb_chars.size < self.page_title[:content_h2_f].mb_chars.size
        serve = self.page_title[:content_h2_f]
      elsif not self.page_title[:itemprop_headline].blank? and
            not self.page_title[:og_title].blank? and
                self.page_title[:og_title].mb_chars.size * 3 > self.page_title[:itemprop_headline].mb_chars.size
        serve = self.page_title[:itemprop_headline]
      elsif not self.page_title[:itemprop_name].blank? and
            not self.page_title[:og_title].blank? and
                self.page_title[:og_title].mb_chars.size * 3 > self.page_title[:itemprop_name].mb_chars.size
        serve = self.page_title[:itemprop_name]
      elsif not self.page_title[:og_title].blank?
        serve = self.page_title[:og_title]
      elsif not self.page_title[:meta_title].blank?
        serve = self.page_title[:meta_title]
      elsif not self.page_title[:title].blank?
        serve = self.page_title[:title]
      elsif not self.page_title[:itemprop_headline].blank?
        serve = self.page_title[:itemprop_headline]
      elsif not self.page_title[:itemprop_name].blank?
        serve = self.page_title[:itemprop_name]
      end
      if serve.blank? or serve.mb_chars.size < 7
        serve = "Новина от #{Time.now.strftime('%d.%m.%Y')}"
      end
      self.page_title[:served] = serve
      # best description
      if    not self.page_summary[:itemprop_description].blank? and
            not self.page_summary[:og_description].blank? and
            not self.page_summary[:itemprop_description] != self.page_summary[:og_description]
        serve = self.page_summary[:itemprop_description]
      elsif not self.page_summary[:itemprop_description].blank? and
            not self.page_summary[:readability].blank? and
            not self.page_summary[:itemprop_description].mb_chars.size < self.page_summary[:readability].mb_chars.size/4
        serve = self.page_summary[:itemprop_description]
      elsif not self.page_summary[:readability].blank?
        serve = self.page_summary[:readability]
      elsif not self.page_summary[:itemprop_articlebody].blank?
        serve = self.page_summary[:itemprop_articlebody]
      elsif not self.page_summary[:itemprop_description].blank?
        serve = self.page_summary[:itemprop_description]
      elsif not self.page_summary[:og_description].blank?
        serve = self.page_summary[:og_description]
      elsif not self.page_summary[:meta_description].blank?
        serve = self.page_summary[:meta_description]
      end
      if serve.blank? or serve.mb_chars.size < 10
        serve = "Новина от #{Time.now.strftime('%d.%m.%Y')}"
      end
      self.page_summary[:served] = serve
      # best photo
      if    not self.page_photo[:itemprop_image].blank?
        serve = self.page_photo[:itemprop_image]
      elsif not self.page_photo[:og_image].blank?
        serve = self.page_photo[:og_image]
      elsif not self.page_photo[:link_rel_image].blank?
        serve = self.page_photo[:link_rel_image]
      elsif not self.page_photo[:assumed_after_h1].blank?
        serve = self.page_photo[:assumed_after_h1]
      elsif not self.page_photo[:assumed_after_h2].blank?
        serve = self.page_photo[:assumed_after_h2]
      #elsif not self.page_photo[:readability].blank?
      #  serve = self.page_photo[:readability]
      else
        serve = ''
      end
      if not serve.blank?
        begin
          serve = URI.decode(serve)
          serve = URI.encode(serve)
        rescue URI::InvalidURIError
          serve = ''
        end
      end
      self.page_photo[:served] = serve
      # best keywords
      serve = Array.new
      if not self.page_keywords[:itemprop_keywords].blank?
        serve << self.page_keywords[:itemprop_keywords]
      end
      if not self.page_keywords[:rel_tag].blank?
        serve << self.page_keywords[:rel_tag]
      end
      # do some fallbacks
      if serve.blank?
        if not self.page_keywords[:assumed_tags].blank? and not self.page_keywords[:assumed_tags].size > 10
          serve << self.page_keywords[:assumed_tags]
        end
        if not self.page_keywords[:meta_tags].blank? and not self.page_keywords[:meta_tags].size > 10
          serve << self.page_keywords[:meta_tags]
        end
        if not self.page_keywords[:meta_keywords].blank? and not self.page_keywords[:meta_keywords].size > 10
          serve << self.page_keywords[:meta_keywords]
        end
      end
      # make keywords in format appropriate
      if not serve.blank?
        self.page_keywords[:served] = serve.join(',')
      else
        self.page_keywords[:served] = "новини"
      end
    end
  end
  
  #def semantics()
  #  timeout(15) do
  #    # keywords
  #    begin
  #      xml_k = rest_xml( self.page_title[:served],
  #                        self.page_summary[:served],
  #                        '')
  #      url_k = RestClient::Resource.new 'http://example.com', 'user', 'pass'
  #      resp_k = url_k.post xml_k, :content_type => 'application/xhtml+xml', :accept => 'application/xhtml+xml'
  #      if not resp_k.blank? and not resp_k.body.blank?
  #        #puts "#########################################################"
  #        #puts resp_k.body.inspect
  #        keywords_k = Hash.from_xml(resp_k.body)['block1']['block2']
  #        #puts keywords_k.inspect
  #        if not keywords_k.blank?
  #          keywords_k = keywords_k['block2']
  #          if keywords_k.kind_of?(Hash)
  #            keywords_k = [keywords_k]
  #          end
  #          self.page_keywords[:semantics_k] = keywords_k.collect{ |k| k['label'] }
  #        else
  #          keywords_k = nil
  #        end
  #      end
  #    rescue Exception => exception
  #      self.errors << "semantic_k: "+exception
  #    end
  #    # categories
  #    begin
  #      xml_c = rest_xml( self.page_title[:served],
  #                        self.page_summary[:served],
  #                        '')
  #      url_c = RestClient::Resource.new 'http://example.com',       'user', 'pass'
  #      resp_c = url_c.post xml_c, :content_type => 'application/xhtml+xml', :accept => 'application/xhtml+xml'
  #      if not resp_c.blank? and not resp_c.body.blank?
  #        #puts "#########################################################"
  #        #puts resp_c.body.inspect
  #        keywords_c = Hash.from_xml(resp_c.body)['block1']['block2']
  #        #puts keywords_c.inspect
  #        if not keywords_c.blank?
  #          if keywords_c['block2'].kind_of?(String)
  #            keywords_c = [keywords_c['block2']]
  #          else
  #            keywords_c = keywords_c['block2']
  #          end
  #          self.page_keywords[:semantics_c] = keywords_c
  #        else
  #          keywords_c = nil
  #        end
  #      end
  #    rescue Exception => exception
  #      self.errors << "semantic_c: "+exception
  #    end
  #    # add to served keywords
  #    serve = self.page_keywords[:served]
  #    serve = serve.split(',')
  #    if not page_keywords.blank?
  #      serve += page_keywords[:semantics_k] if not page_keywords[:semantics_k].blank?
  #      serve += page_keywords[:semantics_c] if not page_keywords[:semantics_c].blank?
  #      # make sure story have LVL1 topics
  #      # temporary disable this to try and improve quality
  #      #main_tags = []
  #      #keywords = serve
  #      #GLOBAL_TOPICS.each do |main_tag, sub_tags|
  #      #  for tag in sub_tags
  #      #    if keywords.include? tag.name
  #      #      main_tags << main_tag.name
  #      #    end
  #      #  end
  #      #end
  #      #serve += main_tags
  #      # continue on
  #      if not serve.blank?
  #        self.page_keywords[:served] = serve.uniq.compact.join(',')
  #      else
  #        self.page_keywords[:served] = "новини"
  #      end
  #    end
  #  end
  #end
  
  private
    
    def normalize(text)
      str = HTMLEntities.new().decode(text)
      str = str.squish
      return str
    end
    
    def rest_xml(title,summary,tags)
      xml    = "<?xml version='1.0' encoding='UTF-8'?>"
      xml   += "<stories>"
      xml   += "<story>"
      xml   += "<title>"+CGI.escapeHTML(title)+"</title>"
      xml   += "<summary>"+CGI.escapeHTML(summary)+"</summary>"
      if not tags.blank?
        xml += "<tags>"
        for tag in tags.split(',')
          xml += "<tag>"+tag+"</tag>"
        end
        xml += "</tags>"
      end
      xml   += "</story>"
      xml   += "</stories>"
    end
    
    def make_absolute_address(path)
      if not path =~ /^http:/
        if path.mb_chars[0,2] == ".."
          path.mb_chars[0,2] = ""
        end
        if not path.mb_chars[0,1] == "/"
          path = "/"+path
        end
        path = ("http://"+self.url_host+path)
      end
      return path
    end
    
end