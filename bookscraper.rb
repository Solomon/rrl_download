require 'nokogiri'
require 'gepub'
require 'open-uri'
require 'pry'

class Chapter
  def initialize(chapter_number)
    @chapter_number = chapter_number
  end

  def chapter_url
    "http://royalroadl.com/fiction/chapter/#{@chapter_number}"
  end

  def chapter_object
    @chapter_object ||= Nokogiri::HTML(open(chapter_url))
  end

  def chapter_title
    chapter_object.css('.fic-header h2').text
  end

  def chapter_text
    chapter_object.css('.chapter-content').to_s
  end

  # remove weird breaking spaces and smart quotes
  def formatted_text
    formatted = chapter_text.gsub(/\u00a0/, ' ').gsub(/[\u2018\u2019]/, '\'').gsub(/[\u201c\u201d]/, '"').gsub('…','...')
    fix_letter = formatted.gsub('ö', 'o').gsub(' ', ' ')
    line_spaced = fix_letter#.gsub("\n","<br>")
    encoded = line_spaced.encode("UTF-8", :invalid => :replace, :undef => :replace, :replace => "?")
    return encoded
  end

  def formatted_chapter
    "<h2>#{chapter_title}</h2><br>" + formatted_text
  end

  def html_text
    #%{<?xml version='1.0' encoding='utf-8'?>
    #  <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    %{<html>
        <head>
          <link href="royal_road.css" type="text/css" rel="stylesheet"/>
        </head>
        <body>
          #{formatted_chapter}
        </body>
      </html>
    }
  end

  def chapter_filename
    'text/' + chapter_title + '.html'
  end

  def create_chapter_file!
    File.open(chapter_filename, 'w') { |file| file.write(html_text) }
    system("tidy -m #{chapter_filename.gsub(' ', '\ ')}")
  end

  def delete_chapter_file!
    File.delete(chapter_filename)
  end
end

class WuxiaChapter < Chapter
  def chapter_url
    @chapter_number
  end

  def chapter_title
    chapter_object.css('.entry-header h1').text
  end

  def chapter_text
    chapter_object.at('div[itemprop="articleBody"]').to_s
  end
end

class Book
  def initialize(book_number)
    @book_number = book_number
  end

  def book_url
    "http://royalroadl.com/fiction/#{@book_number}"
  end

  def book_object
    @book_object ||= Nokogiri::HTML(open(book_url))
  end

  def chapter_links
    book_object.css('a').map{ |link| link['href'] }.select{ |l| l =~ /fiction\/chapter/i }.drop(1)
  end

  def chapter_numbers
    chapter_links.map{ |l| l.split('/').last }
  end

  def book_title
    book_object.css('.fic-header h2').text
  end

  def author
    book_object.css('.fic-header h4').children.last.text
  end

  def chapters
    @chapters ||= chapter_numbers.map{ |n| Chapter.new(n) }
  end

  def book_content
    chapters.map{ |c| {'title' => c.chapter_title, 'text' => c.html_text} }
  end
end

class WuxiaBook < Book
  def book_url
    "http://www.wuxiaworld.com/#{@book_number}"
  end

  def book_page_links
    book_object.css('a').map{ |link| link['href'] }.select{ |l| l =~ /-chapter-/i }
  end

  def chapter_links
    index_strings = book_page_links.map{ |l| l.split('/')[3] }
    index_text = index_strings.group_by(&:itself).values.max_by(&:size).first
    puts index_text
    book_page_links.select{ |l| l =~ /#{index_text}/i }
  end

  def book_title
    title_text = book_object.css('.entry-header h1').text
    title_text.split(' ')[0...-3].join(' ')
  end

  def author
    "unknown"
  end

  def chapters
    @chapters ||= chapter_links.map{ |l| WuxiaChapter.new(l)}
  end
end


class EpubBuilder
  def initialize(book)
    @book = book
    @draft = GEPUB::Book.new
  end

  def set_book_attributes
    @draft.set_unique_identifier(@book.book_url)
    @draft.set_identifier(@book.book_url, 'url')
    @draft.set_title(@book.book_title)
    @draft.set_creator(@book.author, 'aut')
  end

  def add_css
    @draft.add_item('royal_road.css', 'royal_road.css', 'style')
    @draft.add_item('royal_road.css', 'royal_road.css', 'css')
  end

  def add_book_chapters_as_files
    @book.chapters.each do |c|
      c.create_chapter_file!
      item = @draft.add_ordered_item(c.chapter_title, c.chapter_filename)
      item.toc_text_with_id(c.chapter_title, c.chapter_title)
      item.media_type = 'html'
    end
  end

  def add_book_chapters_as_html
    @book.chapters.each do |c|
      begin
        item = @draft.add_ordered_item(c.chapter_title, StringIO.new(c.html_text))
        item.toc_text_with_id(c.chapter_title, c.chapter_title)
        item.media_type = 'html'
      rescue
        binding.pry
      end
    end
  end

  def delete_book_chapters
    @book.chapters.each{ |c| c.delete_chapter_file! }
  end

  def move_to_dropbox(name)
    cmd = "mv \"#{name}\" \"#{Dir.home}/Solomon/Dropbox/Temporary/#{name}\""
    `#{cmd}`
  end

  def build_book
    set_book_attributes
    add_css
    add_book_chapters_as_html
    book_name = @book.book_title + '.epub'
    @draft.generate_epub(book_name)
    move_to_dropbox(book_name)
  end
end

if ARGV[0].to_i == 0
  test_book = WuxiaBook.new(ARGV[0])
  puts 'wuxia'
else
  test_book = Book.new(ARGV[0].to_i)
  puts 'rrl'
end

e = EpubBuilder.new(test_book)
e.build_book
