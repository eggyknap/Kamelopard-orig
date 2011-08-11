# vim:ts=4:sw=4:et:smartindent:nowrap

require 'net/http'
require 'uri'
require 'cgi'
require 'rexml/document'
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
# restrictions
class YahooGeocoder < Geocoder
    def initialize(key)
        @api_key = key
        @proto = 'http'
        @host = 'where.yahooapis.com'
        @path = '/geocode'
        @params = { 'appid' => @api_key }
    end

    def lookup(address)
        http = Net::HTTP.new(@host)
        if address.kind_of? Hash then
            p = @params.merge address
        else
            p = @params.merge( { 'q' => address } )
        end
        q = p.map { |k,v| "#{ CGI.escape(k) }=#{ CGI.escape(v) }" }.join('&')
        u = URI::HTTP.build([nil, @host, nil, @path, q, nil])

        resp = Net::HTTP.get u
#        puts resp
        parse_response resp
    end

    def parse_response(resp)
        d = Document.new(resp)
        raise d.root.elements["/ResultSet/ErrorMessage"] if d.root.elements["/ResultSet/Error"].text.to_i != 0
        r = {}
        ['Error', 'ErrorMessage', 'Locale', 'Quality', 'Found'].map do |t|
            r[t] = d.root.elements["/ResultSet/#{ t }"].text
        end
        puts "Found #{ r['Found'] } elements"
        r['Results'] = []
        d.root.elements["/ResultSet/Result"].each do |e|
            p = {}
            puts e.elements['quality']
#            ['quality', 'latitude', 'longitude', 'offsetlat', 'offsetlon', 'radius',
#                'name', 'line1', 'line2', 'line3', 'line4', 'house', 'street', 'xstreet',
#                'unittype', 'unit', 'postal', 'neighborhood', 'city', 'county', 'state',
#                'country', 'countrycode', 'statecode', 'countycode', 'uzip', 'hash',
#                'woeid', 'woetype'
#            ].map do |t|
#                p[t] = e.elements["#{t}"].text
#            end
            r['Results'] << p
        end
        r
    end
end

g = YahooGeocoder.new('dj0yJmk9Z0pwcTlFa01BR0c4JmQ9WVdrOWFteHlhR05tTjJFbWNHbzlNekkzTURZME5UWXkmcz1jb25zdW1lcnNlY3JldCZ4PTM5')
#g.lookup('3192 S 1940 E Salt Lake City, Utah')
puts g.lookup({ 'city' => 'Portland', 'count' => '100' }).to_s
<?xml version="1.0" encoding="UTF-8"?>
# <ResultSet version="1.0">
#     <Error>0</Error>
#     <ErrorMessage>No error</ErrorMessage>
#     <Locale>us_US</Locale>
#     <Quality>87</Quality>
#     <Found>1</Found>
#     <Result>
#         <quality>87</quality>
#         <latitude>40.700957</latitude>
#         <longitude>-111.835866</longitude>
#         <offsetlat>40.700958</offsetlat>
#         <offsetlon>-111.836036</offsetlon>
#         <radius>500</radius>
#         <name></name>
#         <line1>3192 S 1940 E</line1>
#         <line2>Salt Lake City, UT  84106-3918</line2>
#         <line3></line3>
#         <line4>United States</line4>
#         <house>3192</house>
#         <street>S 1940 E</street>
#         <xstreet></xstreet>
#         <unittype></unittype>
#         <unit></unit>
#         <postal>84106-3918</postal>
#         <neighborhood></neighborhood>
#         <city>Salt Lake City</city>
#         <county>Salt Lake County</county>
#         <state>Utah</state>
#         <country>United States</country>
#         <countrycode>US</countrycode>
#         <statecode>UT</statecode>
#         <countycode></countycode>
#         <uzip>84106</uzip>
#         <hash>68E15391DA0AC231</hash>
#         <woeid>12794129</woeid>
#         <woetype>11</woetype>
#     </Result>
# </ResultSet>
# <!-- gws14.maps.bf1.yahoo.com uncompressed/chunked Wed Aug 10 17:14:02 PDT 2011 -->
# <!-- wws02.geotech.bf1.yahoo.com uncompressed/chunked Wed Aug 10 17:14:02 PDT 2011 -->

