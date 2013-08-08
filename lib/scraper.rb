require 'pry'
require 'net/http'
require 'time'
require 'oj'
require 'json'
require 'redcarpet'

module Scraper
  PAGES = {
    day0: "http://yapcasia.org/2013/talk/schedule?date=2013-09-19&format=json",
    day1: "http://yapcasia.org/2013/talk/schedule?date=2013-09-20&format=json",
    day2: "http://yapcasia.org/2013/talk/schedule?date=2013-09-21&format=json",
  }.freeze
  DOWNLOADED_PATH = File.expand_path("../../cached-download", __FILE__)
end

module Scraper::Content
  def self.fetch
    puts "Fetching content and storing"
    Scraper::PAGES.each do |page, url|
      puts "Fetching: #{url}"
      r = Net::HTTP.get(URI.parse(url))
      if !r.nil? || r != ""
        File.open(Scraper::DOWNLOADED_PATH + "/#{page}.json", "w") {|f|
          f.write r
        }
      end
    end
  end
end

module Scraper
  class Parser
    attr_accessor :current_timeslot, :parsed_talks, :speakers, :dates

    DAYS = ['day0', 'day1', 'day2'].freeze

    def initialize
      self.speakers = {}
      self.parsed_talks = {}
      self.dates = []
    end

    def parse_json
      DAYS.each do |day|
        self.dates << JSON.load(File.read(Scraper::DOWNLOADED_PATH + "/#{day}.json"))
      end
    end

    def process_talk
      dates.each do |date|
        date['talks_by_venue'].each do |talks|
          talks.each do |talk|
            talk['venue'] = date['venue_id2name'][talk['venue_id']]
            yield talk
          end
        end
      end
    end

    def process
      parse_json

      redcarpet = Redcarpet::Markdown.new(Redcarpet::Render::HTML)

      process_talk do |talk|
        time = Time.parse("#{talk['start_on']} +0900")
        parsed_talks[talk['id']] = {
          "description" => redcarpet.render(talk['abstract']),
          "title" => talk['title_en'] || talk['title'],
          "speaker" => {
            "name" => talk['speaker']['name']
            # "description" => ...
          },
          "uid" => talk['id'],
          "location" => talk['venue'],
          "starting_at" => time.to_i * 1000,
          "ending_at"   => (time.to_i + talk['duration'].to_i * 60) * 1000,
          "duration"   => talk['duration'].to_i,
          "venue_id" => talk['venue_id'],
        }
      end

      generate_js
    end

    def generate_js
      to_output = self.parsed_talks.values.reject {|v| v["starting_at"].nil? }.
        sort_by {|v| "#{v["starting_at"]} #{600 - v["duration"]} #{v['venue_id']}" }
      File.open(File.expand_path("../../public/data/schedule.js", __FILE__), "w") do |f|
       f.write "var schedule = #{Oj.dump(to_output)};"
      end
    end
  end
end
