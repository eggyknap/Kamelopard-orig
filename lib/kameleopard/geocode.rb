# vim:ts=4:sw=4:et:smartindent:nowrap

require 'net/http'
require 'uri'
require 'cgi'
require 'rexml/document'
require 'yaml'
include REXML

# Geocoder base class
class Geocoder
    def initialize
        raise "Unimplemented -- some other class should extend Geocoder and replace this initialize method"
    end

    def lookup(address)
        raise "Unimplemented -- some other class should extend Geocoder and replace this lookup method"
    end
end

# Uses Yahoo's PlaceFinder geocoding service: http://developer.yahoo.com/geo/placefinder/guide/requests.html
# Google's would seem most obvious, but since it requires you to display
# results on a map, ... I didn't want to have to evaluate other possible
# restrictions. The argument to the constructor is a PlaceFinder API key, but testing suggests it's actually unnecessary
class YahooGeocoder < Geocoder
    def initialize(key)
        @api_key = key
        @proto = 'http'
        @host = 'where.yahooapis.com'
        @path = '/geocode'
        @params = { 'appid' => @api_key }
    end

    def lookup(address)
        # The argument can be a string, in which case PlaceFinder does the parsing
        # The argument can also be a hash, with several possible keys. See the PlaceFinder documentation for details
        # http://developer.yahoo.com/geo/placefinder/guide/requests.html
        http = Net::HTTP.new(@host)
        if address.kind_of? Hash then
            p = @params.merge address
        else
            p = @params.merge( { 'q' => address } )
        end
        q = p.map { |k,v| "#{ CGI.escape(k) }=#{ CGI.escape(v) }" }.join('&')
        u = URI::HTTP.build([nil, @host, nil, @path, q, nil])

        resp = Net::HTTP.get u
        parse_response resp
    end

    def parse_response(resp)
        d = Document.new(resp)
        raise d.root.elements["/ResultSet/ErrorMessage"] if d.root.elements["/ResultSet/Error"].text.to_i != 0
        r = {}
        ['Error', 'ErrorMessage', 'Locale', 'Quality', 'Found'].map do |t|
            r[t] = d.root.elements["/ResultSet/#{ t }"].text
        end
        r['Results'] = []
        d.elements.each("/ResultSet/Result") do |e|
            p = {}
            ['quality', 'latitude', 'longitude', 'offsetlat', 'offsetlon', 'radius',
                'name', 'line1', 'line2', 'line3', 'line4', 'house', 'street', 'xstreet',
                'unittype', 'unit', 'postal', 'neighborhood', 'city', 'county', 'state',
                'country', 'countrycode', 'statecode', 'countycode', 'uzip', 'hash',
                'woeid', 'woetype'
            ].map do |t|
                a = e.elements["#{t}"].text
                p[t] = a unless a.nil?
            end
            r['Results'] << p
        end
        r
    end
end

g = YahooGeocoder.new('dj0yJmk9Z0pwcTlFa01BR0c4JmQ9WVdrOWFteHlhR05tTjJFbWNHbzlNekkzTURZME5UWXkmcz1jb25zdW1lcnNlY3JldCZ4PTM5')
g = YahooGeocoder.new('')
#g.lookup('3192 S 1940 E Salt Lake City, Utah')
puts g.lookup({ 'city' => 'Kanosh', 'state' => 'Utah', 'count' => '100' }).to_yaml
