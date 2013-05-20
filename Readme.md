Shinso
======

## Welcome to Shinso.rb

Shinso is a tool that will "vampire" content by crawling, parsing and making smart decisions about the page content.

You should be able to use shinso in a Rails 2.3 environment with ruby 1.8 without much hustle.

## Getting Started

1. Put the shunso.rb file in your Ruby on Rails project under the models folder.

2. Requirements

- ruby 1.8+
- rails 2.3+
- zlib
- nokogiri
- sanitize
- htmlentities
- readability
- charguess
- rest-client

3. In your controller simple do

        @shinso = Shinso.new
        timeout(25) do
          if @shinso.crawl(params[:url])
            @shinso.parse()
            @shinso.decision()
            #@shinso.semantics()
          end
        end

   where "semantics" is a way you can call a service to return some custom data back to you

## Contributing

The code is very legacy now. Contributions are welcome as long as they are tested against a bunch of multi-language articles.

## License

Shinso.rb is released under the [MIT License](http://www.opensource.org/licenses/MIT).
