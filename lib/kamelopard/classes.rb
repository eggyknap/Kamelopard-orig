# vim:ts=4:sw=4:et:smartindent:nowrap

# Classes to manage various KML objects. See
# http://code.google.com/apis/kml/documentation/kmlreference.html for a
# description of KML

require 'singleton'
require 'kamelopard/pointlist'
require 'rexml/document'
require 'rexml/element'

@@sequence = 0

def get_next_id   # :nodoc
    @@sequence += 1
    @@sequence
end

#--
# Intelligently adds elements to a KML object. Expects the KML object as the
# first argument, an array as the second.  Each entry in the array is itself an
# array, containing first an Object, and second either a string or a Proc
# object. If the first Object is nil, nothing happens. If it's not nil, then:
#   * if the second element is a string, add a new element to the KML. This
#     string is the element name, and the stringified form of the first element
#     is its text value
#   * if the second element is a proc, call the proc, passing it the KML
#     object, and let the Proc (presumably) add itself to the KML
#++
def kml_array(e, m) # :nodoc
    m.map do |a|
        if ! a[0].nil? then
            if a[1].kind_of? Proc then
                a[1].call(e)
            else
                t = REXML::Element.new a[1]
                t.text = a[0].to_s
                e.elements.add t
            end
        end
    end
end

#--
# Accepts XdX'X.X", XDXmX.XXs, XdXmX.XXs, or X.XXXX with either +/- or N/E/S/W
#++
def convert_coord(a)    # :nodoc
    a = a.to_s.upcase.strip

    mult = 1
    if a =~ /^-/ then
        mult *= -1
    end
    a = a.sub /^\+|-/, ''
    a = a.strip

    if a =~ /[SW]$/ then
        mult *= -1
    end
    a = a.sub /[NESW]$/, ''
    a = a.strip

    if a =~ /^\d+(\.\d+)?$/ then
        # coord needs no transformation
        1
    elsif a =~ /^\d+D\d+M\d+(\.\d+)?S$/ then
        # coord is in dms
        p = a.split /[D"']/
        a = p[0].to_f + (p[2].to_f / 60.0 + p[1].to_f) / 60.0
    elsif a =~ /^\d+D\d+'\d+(\.\d+)?"$/ then
        # coord is in d'"
        p = a.split /[D"']/
        a = p[0].to_f + (p[2].to_f / 60.0 + p[1].to_f) / 60.0
    else
        raise "Couldn't determine coordinate format for #{a}"
    end

    # check that it's within range
    a = a.to_f * mult
    raise "Coordinate #{a} out of range" if a > 180 or a < -180
    return a
end

# Helper function for altitudeMode / gx:altitudeMode elements
def add_altitudeMode(mode, e)
    return if mode.nil?
    if mode == :clampToGround or mode == :relativeToGround or mode == :absolute then
        t = REXML::Element.new 'altitudeMode'
    else
        t = REXML::Element.new 'gx:altitudeMode'
    end
    t.text = mode
    e.elements.add t
end

# Base class for all Kamelopard objects. Manages object ID and a single
# comment string associated with the object
class KMLObject
    attr_accessor :id, :comment

    def initialize(comment = nil)
        @id = "#{self.class.name}_#{ get_next_id }"
        @comment = comment.gsub(/</, '&lt;') unless comment.nil?
    end

    # Returns KML string for this object. Objects should override this method
    def to_kml(elem = nil)
        if not elem.nil? then
            elem.attributes['id'] = @id
        end
        if not @comment.nil? and @comment != '' then
            c = REXML::Comment.new " #{@comment} ", elem
            return c
        end
    end
end

# Abstract base class for KMLPoint and several other classes
class Geometry < KMLObject
end

# Represents a Point in KML.
class KMLPoint < Geometry
    attr_accessor :longitude, :latitude, :altitude, :altitudeMode, :extrude
    def initialize(long, lat, alt=0, altmode=:clampToGround, extrude=false)
        super()
        @longitude = convert_coord(long)
        @latitude = convert_coord(lat)
        @altitude = alt
        @altitudeMode = altmode
        @extrude = extrude
    end
    
    def to_s
        "KMLPoint (#{@longitude}, #{@latitude}, #{@altitude}, mode = #{@altitudeMode}, #{ @extrude ? 'extruded' : 'not extruded' })"
    end

    def to_kml(short = false)
        e = REXML::Element.new 'Point'
        super(e)
        e.attributes['id'] = @id
        c = REXML::Element.new 'coordinates'
        c.text = "#{ @longitude }, #{ @latitude }, #{ @altitude }"
        e.elements.add c

        if not short then
            c = REXML::Element.new 'extrude'
            c.text = @extrude ? 1 : 0
            e.elements.add c

            add_altitudeMode(@altitudeMode, e)
        end

        d = REXML::Document.new
        d.add_element e
        d
    end
end

# Helper class for KML objects which need to know about several points at once
class CoordinateList
    attr_reader :coordinates

    # Accepts an optional array of coordinates in any format add_element
    # accepts
    def initialize(coords = nil)
        # Internally we store coordinates as an array of three-element
        # arrays
        @coordinates = []
        if not coords.nil? then
            add_element coords
        else
            @coordinates = []
        end
    end

    def to_kml(elem = nil)
        e = REXML::Element.new 'coordinates'
        t = ''
        @coordinates.each do |a|
            t << "#{ a[0] },#{ a[1] }"
            t << ",#{ a[2] }" if a.size > 2
            t << ' '
        end
        e.text = t.chomp(' ')
        elem.elements.add e unless elem.nil?
        e
    end

    # Alias for add_element
    def <<(a)
        add_element a
    end

    # Adds one or more elements to this CoordinateList. The argument can be in any of several formats:
    # * An array of arrays of numeric objects, in the form [ longitude,
    #   latitude, altitude (optional) ]
    # * A KMLPoint, or some other object that response to latitude, longitude, and altitude methods
    # * An array of the above
    # * Another CoordinateList, to append to this on
    # Note that this will not accept a one-dimensional array of numbers to add
    # a single point. Instead, create a KMLPoint with those numbers, and pass
    # it to add_element
    def add_element(a)
        if a.kind_of? Enumerable then
            # We've got some sort of array or list. It could be a list of
            # floats, to become one coordinate, or it could be several
            # coordinates
            t = a.to_a.first
            if t.kind_of? Enumerable then
                # At this point we assume we've got an array of float-like
                # objects. The second-level arrays need to have two or three
                # entries -- long, lat, and (optionally) alt
                a.each do |i|
                    if i.size < 2 then
                        raise "There aren't enough objects here to make a 2- or 3-element coordinate"
                    elsif i.size >= 3 then
                        @coordinates << [ i[0].to_f, i[1].to_f, i[2].to_f ]
                    else
                        @coordinates << [ i[0].to_f, i[1].to_f ]
                    end
                end
            elsif t.respond_to? 'longitude' and
                t.respond_to? 'latitude' and
                t.respond_to? 'altitude' then
                # This object can cough up a set of coordinates
                a.each do |i|
                    @coordinates << [i.longitude, i.latitude, i.altitude]
                end
            else
                # I dunno what it is
                raise "Kamelopard can't understand this object as a coordinate"
            end
        elsif a.kind_of? CoordinateList then
            # Append this coordinate list
            @coordinates << a.coordinates
        else
            # This is one element. It better know how to make latitude, longitude, etc.
            if a.respond_to? 'longitude' and
                a.respond_to? 'latitude' and
                a.respond_to? 'altitude' then
                @coordinates << [a.longitude, a.latitude, a.altitude]
            else
                raise "Kamelopard can't understand this object as a coordinate"
            end
        end
    end
end

# Corresponds to the KML LineString object
class LineString < Geometry
    attr_accessor :altitudeOffset, :extrude, :tessellate, :altitudeMode, :drawOrder, :longitude, :latitude, :altitude
    attr_reader :coordinates

    def initialize(coords, altMode = :clampToGround)
        super()
        @altitudeMode = altMode
        set_coords coords
    end

    # Sets @coordinates element
    def set_coords(a)
        if a.kind_of? CoordinateList then
            @coordinates = a
        else
            @coordinates = CoordinateList.new(a)
        end
    end

    # Appends an element to this LineString's CoordinateList. See CoordinateList#add_element
    def <<(a)
        @coordinates << a
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'LineString'
        super(k)
        kml_array(k, [
            [@altitudeOffset, 'gx:altitudeOffset'],
            [@extrude, 'extrude'],
            [@tessellate, 'tessellate'],
            [@drawOrder, 'gx:drawOrder']
        ])
        @coordinates.to_kml(k) unless @coordinates.nil?
        add_altitudeMode @altitudeMode, k
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's LinearRing object
class LinearRing < Geometry
    attr_accessor :altitudeOffset, :extrude, :tessellate, :altitudeMode, :coordinates

    def initialize(coordinates = nil, tessellate = 0, extrude = 0, altitudeMode = :clampToGround, altitudeOffset = nil)
        super()
        if coordinates.nil? then
            @coordinates = nil
        elsif coordinates.kind_of? CoordinateList then
            @coordinates = coordinates
        else
            @coordinates = CoordinateList.new(coordinates)
        end
        @tessellate = tessellate
        @extrude = extrude
        @altitudeMode = altitudeMode
        @altitudeOffset = altitudeOffset
    end

    # Sets @coordinates element
    def set_coords(a)
        if a.kind_of? CoordinateList then
            @coordinates = a
        else
            @coordinates = CoordinateList.new(a)
        end
    end

    # Appends an element to this LinearRing's CoordinateList. See CoordinateList#add_element
    def <<(a)
        @coordinates << a
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'LinearRing'
        super(k)
        kml_array(k, [
            [ @altitudeOffset, 'gx:altitudeOffset' ],
            [ @tessellate, 'tessellate' ],
            [ @extrude, 'extrude' ]
        ])
        add_altitudeMode(@altitudeMode, k)
        @coordinates.to_kml(k)
        elem.elements << k unless elem.nil?
        k
    end
end

# Abstract class corresponding to KML's AbstractView object
class AbstractView < KMLObject
    attr_accessor :timestamp, :timespan, :options, :point, :heading, :tilt, :roll, :range, :altitudeMode
    def initialize(className, point = nil, heading = 0, tilt = 0, roll = 0, range = 0, altitudeMode = :clampToGround)
        raise "className argument must not be nil" if className.nil?
        super()
        @point = point
        @options = {}
        @className = className
        if point.nil? then
            @point = nil
        elsif point.kind_of? Placemark then
            @point = point.point
        else
            @point = point
        end
        @heading = heading
        @tilt = tilt
        @roll = roll
        @range = range
        @altitudeMode = altitudeMode
    end

    def point=(point)
        @point.longitude = point.longitude
        @point.latitude = point.latitude
        @point.altitude = point.altitude
    end

    def longitude
        @point.nil? ? nil : @point.longitude
    end

    def latitude
        @point.nil? ? nil : @point.latitude
    end

    def altitude
        @point.nil? ? nil : @point.altitude
    end

    def longitude=(a)
        if @point.nil? then
            @point = KMLPoint.new(a, 0)
        else
            @point.longitude = a
        end
    end

    def latitude=(a)
        if @point.nil? then
            @point = KMLPoint.new(0, a)
        else
            @point.latitude = a
        end
    end

    def altitude=(a)
        if @point.nil? then
            @point = KMLPoint.new(0, 0, a)
        else
            @point.altitude = a
        end
    end

    def to_kml(elem = nil)
        t = REXML::Element.new @className
        super(t)
        kml_array(t, [
            [ @point.nil? ? nil : @point.longitude, 'longitude' ],
            [ @point.nil? ? nil : @point.latitude, 'latitude' ],
            [ @point.nil? ? nil : @point.altitude, 'altitude' ],
            [ @heading, 'heading' ],
            [ @tilt, 'tilt' ],
            [ @range, 'range' ],
            [ @roll, 'roll' ]
        ])
        add_altitudeMode(@altitudeMode, t)
        if @options.keys.length > 0 then
            vo = REXML::Element.new 'gx:ViewerOptions'
            @options.each do |k, v|
                o = REXML::Element.new 'gx:option'
                o.attributes['name'] = k
                o.attributes['enabled'] = v ? 'true' : 'false'
                vo.elements << o
            end
            t.elements << vo
        end
        if not @timestamp.nil? then
            @timestamp.to_kml(t, 'gx')
        elsif not @timespan.nil? then
            @timespan.to_kml(t, 'gx')
        end
        elem.elements << t unless elem.nil?
        t
    end

    def [](a)
        return @options[a]
    end

    def []=(a, b)
        if not b.kind_of? FalseClass and not b.kind_of? TrueClass then
            raise 'Option value must be boolean'
        end
        if a != :streetview and a != :historicalimagery and a != :sunlight then
            raise 'Option index must be :streetview, :historicalimagery, or :sunlight'
        end
        @options[a] = b
    end
end

# Corresponds to KML's Camera object
class Camera < AbstractView
    def initialize(point = nil, heading = 0, tilt = 0, roll = 0, altitudeMode = :clampToGround)
        super('Camera', point, heading, tilt, roll, nil, altitudeMode)
    end

    def range
        raise "The range element is part of LookAt objects, not Camera objects"
    end

    def range=
        # The range element doesn't exist in Camera objects
    end
end

# Corresponds to KML's LookAt object
class LookAt < AbstractView
    def initialize(point = nil, heading = 0, tilt = 0, range = 0, altitudeMode = :clampToGround)
        super('LookAt', point, heading, tilt, nil, range, altitudeMode)
    end

    def roll
        raise "The roll element is part of Camera objects, not LookAt objects"
    end

    def roll=
        # The roll element doesn't exist in LookAt objects
    end
end

# Abstract class corresponding to KML's TimePrimitive object
class TimePrimitive < KMLObject
end

# Corresponds to KML's TimeStamp object. The @when attribute must be in a format KML understands.
class TimeStamp < TimePrimitive
    attr_accessor :when
    def initialize(t_when)
        super()
        @when = t_when
    end

    def to_kml(elem = nil, ns = nil)
        prefix = ''
        prefix = ns + ':' unless ns.nil?
        
        k = REXML::Element.new "#{prefix}TimeStamp"
        super(k)
        w = REXML::Element.new 'when'
        w.text = @when
        k.elements << w
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's TimeSpan object. @begin and @end must be in a format KML
# understands.
class TimeSpan < TimePrimitive
    attr_accessor :begin, :end
    def initialize(t_begin, t_end)
        super()
        @begin = t_begin
        @end = t_end
    end

    def to_kml(elem = nil, ns = nil)
        prefix = ''
        prefix = ns + ':' unless ns.nil?
        
        k = REXML::Element.new "#{prefix}TimeSpan"
        super(k)
        if not @begin.nil? then
            w = REXML::Element.new 'begin'
            w.text = @begin
            k.elements << w
        end
        if not @end.nil? then
            w = REXML::Element.new 'end'
            w.text = @end
            k.elements << w
            elem.elements << k unless elem.nil?
        end
        k
    end
end

# Support class for Feature object
class Snippet
    attr_accessor :text, :maxLines
    def initialize(text = nil, maxLines = 2)
        @text = text
        @maxLines = maxLines
    end

    def to_kml(elem = nil)
        e = REXML::Element.new 'Snippet'
        e.attributes['maxLines'] = @maxLines
        e.text = @text
        elem.elements << e unless elem.nil?
        e
    end
end

# Abstract class corresponding to KML's Feature object.
class Feature < KMLObject
    # Abatract class
    attr_accessor :visibility, :open, :atom_author, :atom_link, :name,
        :phoneNumber, :snippet, :description, :abstractView,
        :timeprimitive, :styleUrl, :styleSelector, :region, :metadata,
        :extendedData, :styles
    attr_reader :addressDetails

    def initialize (name = nil)
        super()
        @name = name
        @visibility = true
        @open = false
        @styles = []
    end

    def timestamp
        @timeprimitive
    end

    def timespan
        @timeprimitive
    end

    def timestamp=(t)
        @timeprimitive = t
    end

    def timespan=(t)
        @timeprimitive = t
    end

    def addressDetails=(a)
        if a.nil? or a == '' then
            Document.instance.uses_xal = false
        else
            Document.instance.uses_xal = true
        end
        @addressDetails = a
    end

    # This function accepts either a StyleSelector object, or a string
    # containing the desired StyleSelector's @id
    def styleUrl=(a)
        if a.is_a? String then
            @styleUrl = a
        elsif a.respond_to? 'id' then
            @styleUrl = "##{ a.id }"
        else
            @styleUrl = a.to_s
        end
    end

    def self.add_author(o, a)
        e = REXML::Element.new 'atom:name'
        e.text = a
        f = REXML::Element.new 'atom:author'
        f << e
        o << f
    end

    def to_kml(elem = nil)
        elem = REXML::Element.new 'Feature' if elem.nil?
        super(elem)
        kml_array(elem, [
                [@name, 'name'],
                [(@visibility.nil? || @visibility) ? 1 : 0, 'visibility'],
                [(! @open.nil? && @open) ? 1 : 0, 'open'],
                [@atom_author, lambda { |o| Feature.add_author(o, @atom_author) }],
                [@atom_link, 'atom:link'],
                [@address, 'address'],
                [@addressDetails, 'xal:AddressDetails'],
                [@phoneNumber, 'phoneNumber'],
                [@description, 'description'],
                [@styleUrl, 'styleUrl'],
                [@styleSelector, lambda { |o| @styleSelector.to_kml(o) }],
                [@metadata, 'Metadata' ],
                [@extendedData, 'ExtendedData' ]
            ])
        styles_to_kml(elem)
        @snippet.to_kml(elem) unless @snippet.nil?
        @abstractView.to_kml(elem) unless @abstractView.nil?
        @timeprimitive.to_kml(elem) unless @timeprimitive.nil?
        @region.to_kml(elem) unless @region.nil?
        yield(elem) if block_given?
        elem 
    end
    
    def styles_to_kml(elem)
        @styles.each do |a|
            a.to_kml(elem)
        end
    end
end

# Abstract class corresponding to KML's Container object.
class Container < Feature
    def initialize
        super
        @features = []
    end

    # Adds a new object to this container.
    def <<(a)
        @features << a
    end
end

# Corresponds to KML's Folder object.
class Folder < Container
    attr_accessor :styles, :folders, :parent_folder

    def initialize(name = nil)
        super()
        @name = name
        @styles = []
        @folders = []
        Document.instance.folders << self
    end

    def to_kml(elem = nil)
        h = REXML::Element.new 'Folder'
        super h
        @features.each do |a|
            a.to_kml(h)
        end
        @folders.each do |a|
            a.to_kml(h)
        end
        elem.elements << h unless elem.nil?
        h
    end

    # Folders can have parent folders; returns true if this folder has one
    def has_parent?
        not @parent_folder.nil?
    end

    # Folders can have parent folders; sets this folder's parent
    def parent_folder=(a)
        @parent_folder = a
        a.folders << self
    end
end

def get_stack_trace   # :nodoc
    k = ''
    caller.each do |a| k << "#{a}\n" end
    k
end

# Represents KML's Document class. This is a Singleton object; Kamelopard
# scripts can (for now) manage only one Document at a time.
class Document < Container
    include Singleton
    attr_accessor :flyto_mode, :folders, :tours, :uses_xal

    def initialize
        super
        @tours = []
        @folders = []
        @styles = []
    end

    # Returns the current Tour object
    def tour
        @tours << Tour.new if @tours.length == 0
        @tours.last
    end

    # Returns the current Folder object
    def folder
        if @folders.size == 0 then
            Folder.new
        end
        @folders.last
    end

#    def styles_to_kml(elem = nil)
#    end

    def get_kml_document
        k = REXML::Document.new
        k << REXML::XMLDecl.default
        r = REXML::Element.new('kml')
        if @uses_xal then
            r.attributes['xmlns:xal'] = "urn:oasis:names:tc:ciq:xsdschema:xAL:2.0"
        end
        r.attributes['xmlns'] = 'http://www.opengis.net/kml/2.2'
        r.attributes['xmlns:gx'] = 'http://www.google.com/kml/ext/2.2'
        r.attributes['xmlns:kml'] = 'http://www.opengis.net/kml/2.2'
        r.attributes['xmlns:atom'] = 'http://www.w3.org/2005/Atom'
        r.elements << self.to_kml
        k << r
        k
    end

    def to_kml
        d = REXML::Element.new 'Document'
        super(d)

        # Print styles first
        @styles.map do |a| a.to_kml(d) unless a.attached? end

        # then folders
        @folders.map do |a|
            a.to_kml(d) unless a.has_parent?
        end

        # then tours
        @tours.map do |a| a.to_kml(d) end

        d
    end
end

# Corresponds to KML's ColorStyle object. Color is stored as an 8-character hex
# string, with two characters each of alpha, blue, green, and red values, in
# that order, matching the ordering the KML spec demands.
class ColorStyle < KMLObject
    attr_accessor :color
    attr_reader :colorMode
    
    def initialize(color, colorMode = :normal)
        super()
        # Note: color element order is aabbggrr
        @color = color
        validate_colorMode colorMode
        @colorMode = colorMode # Can be :normal or :random
    end

    def validate_colorMode(a)
        raise "colorMode must be either \"normal\" or \"random\"" unless a == :normal or a == :random
    end

    def colorMode=(a)
        validate_colorMode a
        @colorMode = a
    end

    def alpha
        @color[0,2]
    end

    def alpha=(a)
        @color[0,2] = a
    end

    def blue
        @color[2,2]
    end

    def blue=(a)
        @color[2,2] = a
    end

    def green
        @color[4,2]
    end

    def green=(a)
        @color[4,2] = a
    end

    def red
        @color[6,2]
    end

    def red=(a)
        @color[6,2] = a
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'ColorStyle'
        super k
        e = REXML::Element.new 'color'
        e.text = @color
        k.elements << e
        e = REXML::Element.new 'colorMode'
        e.text = @colorMode
        k.elements << e
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's BalloonStyle object. Color is stored as an 8-character hex
# string, with two characters each of alpha, blue, green, and red values, in
# that order, matching the ordering the KML spec demands.
class BalloonStyle < ColorStyle
    attr_accessor :bgcolor, :text, :textcolor, :displaymode

    # Note: color element order is aabbggrr
    def initialize(text = '', textcolor = 'ff000000', bgcolor = 'ffffffff', displaymode = :default)
        super(nil, :normal)
        @bgcolor = bgcolor
        @text = text
        @textcolor = textcolor
        @displaymode = displaymode
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'BalloonStyle'
        super k
        kml_array(k, [
            [ @bgcolor, 'bgColor' ],
            [ @text, 'text' ],
            [ @textcolor, 'textColor' ],
            [ @displayMode, 'displayMode' ]
        ])
        elem.elements << k unless elem.nil
        k
    end
end

# Internal class used where KML requires X and Y values and units
class KMLxy
    attr_accessor :x, :y, :xunits, :yunits
    def initialize(x = 0.5, y = 0.5, xunits = :fraction, yunits = :fraction)
        @x = x
        @y = y
        @xunits = xunits
        @yunits = yunits
    end

    def to_kml(name, elem = nil)
        k = REXML::Element.new name
        k.attributes['x'] = @x
        k.attributes['y'] = @y
        k.attributes['xunits'] = @xunits
        k.attributes['yunits'] = @yunits
        elem.elements << k unless elem.nil
        k
    end
end

# Corresponds to the KML Icon object
class Icon
    attr_accessor :href, :x, :y, :w, :h, :refreshMode, :refreshInterval, :viewRefreshMode, :viewRefreshTime, :viewBoundScale, :viewFormat, :httpQuery

    def initialize(href = nil)
        @href = href
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'Icon'
        kml_array(k, [
            [@href, 'href'],
            [@x, 'gx:x'],
            [@y, 'gx:y'],
            [@w, 'gx:w'],
            [@h, 'gx:h'],
            [@refreshMode, 'refreshMode'],
            [@refreshInterval, 'refreshInterval'],
            [@viewRefreshMode, 'viewRefreshMode'],
            [@viewBoundScale, 'viewBoundScale'],
            [@viewFormat, 'viewFormat'],
            [@httpQuery, 'httpQuery'],
        ])
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's IconStyle object.
class IconStyle < ColorStyle
    attr_accessor :scale, :heading, :hotspot, :icon

    def initialize(href, scale = 1, heading = 0, hs_x = 0.5, hs_y = 0.5, hs_xunits = :fraction, hs_yunits = :fraction, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @scale = scale
        @heading = heading
        @icon = Icon.new(href) unless href.nil?
        @hotspot = KMLxy.new(hs_x, hs_y, hs_xunits, hs_yunits) unless (hs_x.nil? and hs_y.nil? and hs_xunits.nil? and hs_yunits.nil?)
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'IconStyle'
        super(k)
        kml_array( k, [
            [ @scale, 'scale' ],
            [ @heading, 'heading' ]
        ])
        if not @hotspot.nil? then
            h = REXML::Element.new 'hotSpot'
            h.attributes['x'] = @hotspot.x
            h.attributes['y'] = @hotspot.y
            h.attributes['xunits'] = @hotspot.xunits
            h.attributes['yunits'] = @hotspot.yunits
            k.elements << h
        end
        @icon.to_kml(k) unless @icon.nil?
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's LabelStyle object
class LabelStyle < ColorStyle
    attr_accessor :scale

    def initialize(scale = 1, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @scale = scale
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'LabelStyle'
        super k
        s = REXML::Element.new 'scale'
        s.text = @scale
        k.elements << s
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's LineStyle object. Color is stored as an 8-character hex
# string, with two characters each of alpha, blue, green, and red values, in
# that order, matching the ordering the KML spec demands.
class LineStyle < ColorStyle
    attr_accessor :outercolor, :outerwidth, :physicalwidth, :width

    def initialize(width = 1, outercolor = 'ffffffff', outerwidth = 0, physicalwidth = 0, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @width = width
        @outercolor = outercolor
        @outerwidth = outerwidth
        @physicalwidth = physicalwidth
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'LineStyle'
        super k
        kml_array(k, [
            [ @width, 'width' ],
            [ @outercolor, 'gx:outerColor' ],
            [ @outerwidth, 'gx:outerWidth' ],
            [ @physicalwidth, 'gx:physicalWidth' ],
        ])
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's ListStyle object. Color is stored as an 8-character hex
# string, with two characters each of alpha, blue, green, and red values, in
# that order, matching the ordering the KML spec demands.
class ListStyle < ColorStyle
    attr_accessor :listitemtype, :bgcolor, :state, :href

    def initialize(bgcolor = nil, state = nil, href = nil, listitemtype = nil)
        super(nil, :normal)
        @bgcolor = bgcolor
        @state = state
        @href = href
        @listitemtype = listitemtype
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'ListStyle'
        super k
        kml_array(k, [
            [@listitemtype, 'listItemType'],
            [@bgcolor, 'bgColor']
        ])
        if (! @state.nil? or ! @href.nil?) then
            i = REXML::Element.new 'ItemIcon'
            kml_array(i, [
                [ @state, 'state' ],
                [ @href, 'href' ]
            ])
            k.elements << i
        end
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's PolyStyle object. Color is stored as an 8-character hex
# string, with two characters each of alpha, blue, green, and red values, in
# that order, matching the ordering the KML spec demands.
class PolyStyle < ColorStyle
    attr_accessor :fill, :outline

    def initialize(fill = 1, outline = 1, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @fill = fill
        @outline = outline
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'PolyStyle'
        super k
        kml_array( k, [
            [ @fill, 'fill' ],
            [ @outline, 'outline' ]
        ])
        elem.elements << k unless elem.nil?
        k
    end
end

# Abstract class corresponding to KML's StyleSelector object.
class StyleSelector < KMLObject
    attr_accessor :attached
    def initialize
        super
        @attached = false
        Document.instance.styles << self
    end

    def attached?
        @attached
    end

    def attach(obj)
        @attached = true
        obj.styles << self
    end
end

# Corresponds to KML's Style object. Attributes are expected to be IconStyle,
# LabelStyle, LineStyle, PolyStyle, BalloonStyle, and ListStyle objects.
class Style < StyleSelector
    attr_accessor :icon, :label, :line, :poly, :balloon, :list
    def initialize(icon = nil, label = nil, line = nil, poly = nil, balloon = nil, list = nil)
        super()
        @icon = icon
        @label = label
        @line = line
        @poly = poly
        @balloon = balloon
        @list = list
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'Style'
        super(k)
        @icon.to_kml(k) unless @icon.nil?
        @label.to_kml(k) unless @label.nil?
        @line.to_kml(k) unless @line.nil?
        @poly.to_kml(k) unless @poly.nil?
        @balloon.to_kml(k) unless @balloon.nil?
        @list.to_kml(k) unless @list.nil?
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's StyleMap object.
class StyleMap < StyleSelector
    # StyleMap manages pairs. The first entry in each pair is a string key, the
    # second is either a Style or a styleUrl. It will be assumed to be the
    # latter if its kind_of? method doesn't claim it's a Style object
    def initialize(pairs = {})
        super()
        @pairs = pairs
    end

    # Adds a new Style to the StyleMap.
    def merge(a)
        @pairs.merge(a)
    end

    def to_kml(elem = nil)
        t = REXML::Element.new 'StyleMap'
        super t
        @pairs.each do |k, v|
            p = REXML::Element.new 'Pair'
            key = REXML::Element.new 'key'
            key.text = k
            p.elements << key 
            if v.kind_of? Style then
                v.to_kml(p)
            else
                s = REXML::Element.new 'styleUrl'
                s.text = v
                p.elements << s
            end
            t.elements << p
        end
        elem.elements << t unless elem.nil?
        t
    end
end

# Corresponds to KML's Placemark objects. The geometry attribute requires a
# descendant of Geometry
class Placemark < Feature
    attr_accessor :name, :geometry
    def initialize(name = nil, geo = nil)
        super(name)
        if geo.respond_to? '[]' then
            @geometry = geo
        else
            @geometry = [ geo ]
        end
    end
    
    def to_kml(indent = 0)
        a = "#{ ' ' * indent }<Placemark id=\"#{ @id }\">\n"
        a << super(indent + 4) {
            k = ''
            @geometry.each do |i| k << i.to_kml(indent + 4) unless i.nil? end
            k
        }
        a << "#{ ' ' * indent }</Placemark>\n"
    end

    def to_s
        "Placemark id #{ @id } named #{ @name }"
    end

    def longitude
        @geometry.longitude
    end

    def latitude
        @geometry.latitude
    end

    def altitude
        @geometry.altitude
    end

    def altitudeMode
        @geometry.altitudeMode
    end

    def point
        if @geometry[0].kind_of? KMLPoint then
            @geometry[0]
        else
            raise "This placemark uses a non-point geometry, but the operation you're trying requires a point object"
        end
    end
end

# Abstract class corresponding to KML's gx:TourPrimitive object. Tours are made up
# of descendants of these.
class TourPrimitive < KMLObject
    def initialize
        Document.instance.tour << self
    end
end

# Cooresponds to KML's gx:FlyTo object. The @view parameter needs to look like an
# AbstractView object
class FlyTo < TourPrimitive
    attr_accessor :duration, :mode, :view

    def initialize(view = nil, range = nil, duration = 0, mode = :bounce)
        @duration = duration
        @mode = mode
        if view.kind_of? AbstractView then
            @view = view
        else
            @view = LookAt.new(view)
        end
        if view.respond_to? 'range' and not range.nil? then
            @view.range = range
        end
        super()
    end

    def to_kml(indent = 0)
        k = super + "#{ ' ' * indent }<gx:FlyTo>\n"
        k << kml_array([
            [ @duration, 'gx:duration' ],
            [ @mode, 'gx:flyToMode' ]
        ], indent + 4)
        k << @view.to_kml(indent + 4) unless @view.nil?
        k << "#{ ' ' * indent }</gx:FlyTo>\n"
    end
end

# Corresponds to KML's gx:AnimatedUpdate object. For now at least, this isn't very
# intelligent; you've got to manually craft the <Change> tag(s) within the
# object.
class AnimatedUpdate < TourPrimitive
    # For now, the user has to specify the change / create / delete elements in
    # the <Update> manually, rather than creating objects.
    attr_accessor :target, :delayedstart, :updates, :duration

    # The updates argument is an array of strings containing <Change> elements
    def initialize(updates = [], duration = 0, target = '', delayedstart = nil)
        super()
        begin
            raise "incorrect object type" unless @target.kind_of? KMLObject
            @target = target.id
        rescue RuntimeError
            @target = target
        end
        @updates = updates
        @duration = duration
        @delayedstart = delayedstart
    end

    # Adds another update string, presumably containing a <Change> element
    def <<(a)
        @updates << a << "\n"
    end

    def to_kml(indent = 0)
        k = super + <<-animatedupdate_kml
#{ ' ' * indent }<gx:AnimatedUpdate>
#{ ' ' * indent }    <gx:duration>#{@duration}</gx:duration>
        animatedupdate_kml
        k << "#{ ' ' * indent }    <gx:delayeStart>#{@delayedstart}</gx:delayedStart>\n" unless @delayedstart.nil?
        k << "#{ ' ' * indent }    <Update>\n"
        k << "#{ ' ' * indent }        <targetHref>#{@target}</targetHref>\n"
        k << "#{ ' ' * indent }        " << @updates.join("\n#{ ' ' * (indent + 1) }")
        k << "#{ ' ' * indent }    </Update>\n#{ ' ' * indent }</gx:AnimatedUpdate>\n"
        k
    end
end

# Corresponds to a KML gx:TourControl object
class TourControl < TourPrimitive
    def initialize
        super
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<gx:TourControl id=\"#{ @id }\">\n"
        k << "#{ ' ' * indent }    <gx:playMode>pause</gx:playMode>\n"
        k << "#{ ' ' * indent }</gx:TourControl>\n"
    end
end

# Corresponds to a KML gx:Wait object
class Wait < TourPrimitive
    attr_accessor :duration
    def initialize(duration = 0)
        super()
        @duration = duration
    end

    def to_kml(indent = 0)
        super + <<-wait_kml
#{ ' ' * indent }<gx:Wait><gx:duration>#{@duration}</gx:duration></gx:Wait>
        wait_kml
    end
end

# Corresponds to a KML gx:SoundCue object
class SoundCue < TourPrimitive
    attr_accessor :href, :delayedStart
    def initialize(href, delayedStart = nil)
        super()
        @href = href
        @delayedStart = delayedStart
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<gx:SoundCue id=\"#{ @id }\">\n"
        k << "#{ ' ' * indent }    <href>#{ @href }</href>\n"
        k << "#{ ' ' * indent }    <gx:delayedStart>#{ @delayedStart }</gx:delayedStart>\n" unless @delayedStart.nil?
        k << "#{ ' ' * indent}</gx:SoundCue>\n"
    end
end

# Corresponds to a KML gx:Tour object
class Tour < KMLObject
    attr_accessor :name, :description, :last_abs_view
    def initialize(name = nil, description = nil)
        super()
        @name = name
        @description = description
        @items = []
    end

    # Add another element to this Tour
    def <<(a)
        @items << a
        @last_abs_view = a.view if a.kind_of? FlyTo
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'gx:Tour'
        super k
        kml_array([
            [ @name, 'name' ],
            [ @description, 'description' ],
        ], k)
        p = REXML::Element.new 'gx:Playlist'
        @items.map do |a| a.to_kml p end
        elem << k unless elem.nil?
        k
    end
end

# Abstract class corresponding to the KML Overlay object
class Overlay < Feature
    attr_accessor :color, :drawOrder, :icon

    def initialize(icon, name = nil)
        super(name)
        Document.instance.folder << self
        if icon.respond_to?('to_kml') then
            @icon = icon
        elsif not icon.nil?
            @icon = Icon.new(icon.to_s)
        end
    end

    def to_kml(indent = 0)
        k = super(indent) + kml_array([
            [ @color, 'color' ],
            [ @drawOrder, 'drawOrder' ],
        ], indent + 4)
        k << @icon.to_kml(indent) unless @icon.nil?
        k
    end
end

# Corresponds to KML's ScreenOverlay object
class ScreenOverlay < Overlay
    attr_accessor :overlayXY, :screenXY, :rotationXY, :size, :rotation
    def initialize(icon, name  = nil, size = nil, rotation = nil, overlayXY = nil, screenXY = nil, rotationXY = nil)
        super(icon, name)
        @overlayXY = overlayXY
        @screenXY = screenXY
        @rotationXY = rotationXY
        @size = size
        @rotation = rotation
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<ScreenOverlay id=\"#{ @id }\">\n"
        k << super(indent + 4)
        k << @overlayXY.to_kml('overlayXY', indent + 4)   unless @overlayXY.nil?
        k << @screenXY.to_kml('screenXY', indent + 4)     unless @screenXY.nil?
        k << @rotationXY.to_kml('rotationXY', indent + 4) unless @rotationXY.nil?
        k << @size.to_kml('size', indent + 4)             unless @size.nil?
        k << "#{ ' ' * indent }    <rotation>#{ @rotation }</rotation>\n" unless @rotation.nil?
        k << "#{ ' ' * indent }</ScreenOverlay>\n"
    end
end

# Supporting object for the PhotoOverlay class
class ViewVolume
    attr_accessor :leftFov, :rightFov, :bottomFov, :topFov, :near
    def initialize(near, leftFov = -45, rightFov = 45, bottomFov = -45, topFov = 45)
        @leftFov = leftFov
        @rightFov = rightFov
        @bottomFov = bottomFov
        @topFov = topFov
        @near = near
    end

    def to_kml(indent = 0)

        <<-viewvolume
#{ ' ' * indent }<ViewVolume>
#{ ' ' * indent }    <near>#{@near}</near>
#{ ' ' * indent }    <leftFov>#{@leftFov}</leftFov>
#{ ' ' * indent }    <rightFov>#{@rightFov}</rightFov>
#{ ' ' * indent }    <bottomFov>#{@bottomFov}</bottomFov>
#{ ' ' * indent }    <topFov>#{@topFov}</topFov>
#{ ' ' * indent }</ViewVolume>
        viewvolume
    end
end

# Supporting object for the PhotoOverlay class
class ImagePyramid
    attr_accessor :tileSize, :maxWidth, :maxHeight, :gridOrigin

    def initialize(maxWidth, maxHeight, gridOrigin, tileSize = 256)
        @tileSize = tileSize
        @maxWidth = maxWidth
        @maxHeight = maxHeight
        @gridOrigin = gridOrigin
    end

    def to_kml(indent = 0)
        
        <<-imagepyramid
#{ ' ' * indent }<ImagePyramid>
#{ ' ' * indent }    <tileSize>#{@tileSize}</tileSize>
#{ ' ' * indent }    <maxWidth>#{@maxWidth}</maxWidth>
#{ ' ' * indent }    <maxHeight>#{@maxHeight}</maxHeight>
#{ ' ' * indent }    <gridOrigin>#{@gridOrigin}</gridOrigin>
#{ ' ' * indent }</ImagePyramid>
        imagepyramid
    end
end

# Corresponds to KML's PhotoOverlay class
class PhotoOverlay < Overlay
    attr_accessor :rotation, :viewvolume, :imagepyramid, :point, :shape

    def initialize(icon, point, rotation = 0, viewvolume = nil, imagepyramid = nil, shape = :rectangle)
        super(icon)
        if point.respond_to?('point')
            @point = point.point
        else
            @point = point
        end
        @rotation = rotation
        @viewVolume = viewvolume
        @imagePyramid = imagepyramid
        @shape = shape
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<PhotoOverlay>\n"
        k << super(indent + 4)
        k << @viewVolume.to_kml(indent + 4) unless @viewVolume.nil?
        k << @imagePyramid.to_kml(indent + 4) unless @imagePyramid.nil?
        k << @point.to_kml(indent + 4, true)
        k << "#{ ' ' * indent }    <rotation>#{ @rotation }</rotation>\n"
        k << "#{ ' ' * indent }    <shape>#{ @shape }</shape>\n"
        k << "#{ ' ' * indent }</PhotoOverlay>\n"
    end
end

# Corresponds to KML's LatLonBox and LatLonAltBox
class LatLonBox
    attr_reader :north, :south, :east, :west
    attr_accessor :rotation, :minAltitude, :maxAltitude, :altitudeMode

    def initialize(north, south, east, west, rotation = 0, minAltitude = nil, maxAltitude = nil, altitudeMode = :clampToGround)
        @north = convert_coord north
        @south = convert_coord south
        @east = convert_coord east
        @west = convert_coord west
        @minAltitude = minAltitude
        @maxAltitude = maxAltitude
        @altitudeMode = altitudeMode
        @rotation = rotation
    end

    def north=(a)
        @north = convert_coord a
    end

    def south=(a)
        @south = convert_coord a
    end

    def east=(a)
        @east = convert_coord a
    end

    def west=(a)
        @west = convert_coord a
    end

    def to_kml(elem = nil, alt = false)
        name = alt ? 'LatLonAltBox' : 'LatLonBox'
        k = REXML::Element.new name
        [
            ['north', @north], 
            ['south', @south], 
            ['east', @east], 
            ['west', @west],
            ['minAltitude', @minAltitude],
            ['maxAltitude', @maxAltitude]
        ].each do |a|
            if not a[1].nil? then
                m = REXML::Element.new a[0]
                m.text = a[1]
                k.elements << m
            end
        end
        if (not @minAltitude.nil? or not @maxAltitude.nil?) then
            add_altitudeMode(mode, k)
        end
        m = REXML::Element.new 'rotation'
        m.text = @rotation
        k.elements << m
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to KML's gx:LatLonQuad object
class LatLonQuad
    attr_accessor :lowerLeft, :lowerRight, :upperRight, :upperLeft
    def initialize(lowerLeft, lowerRight, upperRight, upperLeft)
        @lowerLeft = lowerLeft
        @lowerRight = lowerRight
        @upperRight = upperRight
        @upperLeft = upperLeft
    end

    def to_kml(indent = 0)

        <<-latlonquad
#{ ' ' * indent }<gx:LatLonQuad>
#{ ' ' * indent }    <coordinates>#{ @lowerLeft.longitude },#{ @lowerLeft.latitude } #{ @lowerRight.longitude },#{ @lowerRight.latitude } #{ @upperRight.longitude },#{ @upperRight.latitude } #{ @upperLeft.longitude },#{ @upperLeft.latitude }</coordinates>
#{ ' ' * indent }</gx:LatLonQuad>
        latlonquad
    end
end

# Corresponds to KML's GroundOverlay object
class GroundOverlay < Overlay
    attr_accessor :altitude, :altitudeMode, :latlonbox, :latlonquad
    def initialize(icon, latlonbox = nil, latlonquad = nil, altitude = 0, altitudeMode = :clampToGround)
        super(icon)
        @latlonbox = latlonbox
        @latlonquad = latlonquad
        @altitude = altitude
        @altitudeMode = altitudeMode
    end

    def to_kml(indent = 0)
        raise "Either latlonbox or latlonquad must be non-nil" if @latlonbox.nil? and @latlonquad.nil?

        k = "#{ ' ' * indent}<GroundOverlay id=\"#{ @id }\">\n"
        k << super(indent + 4)
        k << "#{ ' ' * indent }    <altitude>#{ @altitude }</altitude>\n"
        k << ' ' * indent
        add_altitudeMode(mode, k)
        k << @latlonbox.to_kml(indent + 4) unless @latlonbox.nil?
        k << @latlonquad.to_kml(indent + 4) unless @latlonquad.nil?
        k << "#{ ' ' * indent }</GroundOverlay>\n"
        k
    end
end

# Corresponds to the LOD (Level of Detail) object
class Lod
    attr_accessor :minpixels, :maxpixels, :minfade, :maxfade
    def initialize(minpixels, maxpixels, minfade, maxfade)
        @minpixels = minpixels
        @maxpixels = maxpixels
        @minfade = minfade
        @maxfade = maxfade
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'Lod'
        m = REXML::Element.new 'minLodPixels'
        m.text = @minpixels
        k.elements << m
        m = REXML::Element.new 'maxLodPixels'
        m.text = @maxpixels
        k.elements << m
        m = REXML::Element.new 'minFadeExtent'
        m.text = @minfade
        k.elements << m
        m = REXML::Element.new 'maxFadeExtent'
        m.text = @maxfade
        k.elements << m
        elem.elements << k unless elem.nil?
        k
    end
end

# Corresponds to the KML Region object
class Region < KMLObject
    attr_accessor :latlonaltbox, :lod

    def initialize(latlonaltbox, lod)
        super()
        @latlonaltbox = latlonaltbox
        @lod = lod
    end

    def to_kml(elem = nil)
        k = REXML::Element.new 'Region'
        super(k)
        @latlonaltbox.to_kml(k, true) unless @latlonaltbox.nil?
        @lod.to_kml(k) unless @lod.nil?
        elem.elements << k unless elem.nil?
        k
    end
end

# Sub-object in the KML Model class
class Orientation
    attr_accessor :heading, :tilt, :roll
    def initialize(heading, tilt, roll)
        @heading = heading
        raise "Heading should be between 0 and 360 inclusive; you gave #{ heading }" unless @heading <= 360 and @heading >= 0
        @tilt = tilt
        raise "Tilt should be between 0 and 180 inclusive; you gave #{ tilt }" unless @tilt <= 180 and @tilt >= 0
        @roll = roll
        raise "Roll should be between 0 and 180 inclusive; you gave #{ roll }" unless @roll <= 180 and @roll >= 0
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Orientation>\n"
        k << "#{ ' ' * indent }    <heading>#{ @heading }</heading>\n"
        k << "#{ ' ' * indent }    <tilt>#{ @tilt }</tilt>\n"
        k << "#{ ' ' * indent }    <roll>#{ @roll }</roll>\n"
        k << "#{ ' ' * indent }</Orientation>\n"
        k
    end
end

# Sub-object in the KML Model class
class Scale
    attr_accessor :x, :y, :z
    def initialize(x, y, z = 1)
        @x = x
        @y = y
        @z = z
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Scale>\n"
        k << "#{ ' ' * indent }    <x>#{ x }</x>\n"
        k << "#{ ' ' * indent }    <y>#{ y }</y>\n"
        k << "#{ ' ' * indent }    <z>#{ z }</z>\n"
        k << "#{ ' ' * indent }</Scale>\n"
    end
end

# Sub-object in the KML ResourceMap class
class Alias
    attr_accessor :targetHref, :sourceHref
    def initialize(targetHref = nil, sourceHref = nil)
        @targetHref = targetHref
        @sourceHref = sourceHref
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Alias>\n"
        k << "#{ ' ' * indent }    <targetHref>#{ @targetHref }</targetHref>\n"
        k << "#{ ' ' * indent }    <sourceHref>#{ @sourceHref }</sourceHref>\n"
        k << "#{ ' ' * indent }</Alias>\n"
        k
    end
end

# Sub-object in the KML Model class
class ResourceMap
    attr_accessor :aliases
    def initialize(aliases = [])
        @aliases = []
        if not aliases.nil? then
            if aliases.kind_of? Enumerable then
                @aliases += aliases
            else
                @aliases << aliases
            end
        end
    end

    def to_kml(indent = 0)
        return '' if @aliases.size == 0
        k = "#{ ' ' * indent }<ResourceMap>\n"
        k << "#{ ' ' * indent }</ResourceMap>\n"
        @aliases.each do |a| k << a.to_kml(indent + 4) end
        k
    end
end

# Corresponds to KML's Link object
class Link < KMLObject
    attr_accessor :href, :refreshMode, :refreshInterval, :viewRefreshMode, :viewBoundScale, :viewFormat, :httpQuery
    def initialize(href = '', refreshMode = :onChange, viewRefreshMode = :never)
        super()
        @href = href
        @refreshMode = refreshMode
        @viewRefreshMode = viewRefreshMode
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Link id=\"#{ @id }\">\n"
        k << "#{ ' ' * indent }    <href>#{ @href }</href>\n"
        k << "#{ ' ' * indent }    <refreshMode>#{ @refreshMode }</refreshMode>\n"
        k << "#{ ' ' * indent }    <viewRefreshMode>#{ @viewRefreshMode }</viewRefreshMode>\n"
        k << "#{ ' ' * indent }    <refreshInterval>#{ @refreshInterval }</refreshInterval>\n" unless @refreshInterval.nil?
        k << "#{ ' ' * indent }    <viewBoundScale>#{ @viewBoundScale }</viewBoundScale>\n" unless @viewBoundScale.nil?
        k << "#{ ' ' * indent }    <viewFormat>#{ @viewFormat }</viewFormat>\n" unless @viewFormat.nil?
        k << "#{ ' ' * indent }    <httpQuery>#{ @httpQuery }</httpQuery>\n" unless @httpQuery.nil?
        k << "#{ ' ' * indent }</Link>\n"
        k
    end
end

# Corresponds to the KML Model class
class Model < Geometry
    attr_accessor :link, :location, :orientation, :scale, :resourceMap

    # location should be a KMLPoint, or some object that can behave like one,
    # including a Placemark. Model will get its Location and altitudeMode data
    # from this attribute
    def initialize(link, location, orientation, scale, resourceMap)
        super()
        @link = link
        @location = location
        @orientation = orientation
        @scale = scale
        @resourceMap = resourceMap
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Model id=\"#{ @id }\">\n"
        k << @link.to_kml(indent + 4)
        add_altitudeMode(@location.altitudeMode, k)
        k << "#{ ' ' * indent }    <Location>\n"
        k << "#{ ' ' * indent }        <longitude>#{ @location.longitude }</longitude>\n"
        k << "#{ ' ' * indent }        <latitude>#{ @location.latitude }</latitude>\n"
        k << "#{ ' ' * indent }        <altitude>#{ @location.altitude }</altitude>\n"
        k << "#{ ' ' * indent }    </Location>\n"
        k << @orientation.to_kml(indent + 4)
        k << @scale.to_kml(indent + 4)
        k << @resourceMap.to_kml(indent + 4)
        k << "#{ ' ' * indent }</Model>\n"
        k
    end
end
