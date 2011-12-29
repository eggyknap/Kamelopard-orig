# vim:ts=4:sw=4:et:smartindent:nowrap

# Classes to manage various KML objects. See
# http://code.google.com/apis/kml/documentation/kmlreference.html for a
# description of KML

module Kamelopard
    require 'singleton'
    require 'kamelopard/pointlist'
    require 'xml'
    require 'yaml'

    @@sequence = 0

    def Kamelopard.get_document
        Document.instance
    end

    def Kamelopard.get_next_id   # :nodoc
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
    def Kamelopard.kml_array(e, m) # :nodoc
        m.map do |a|
            if ! a[0].nil? then
                if a[1].kind_of? Proc then
                    a[1].call(e)
                elsif a[0].kind_of? XML::Node then
                    d = XML::Node.new(a[1])
                    d << a[0]
                    e << d
                else
                    t = XML::Node.new a[1]
                    t << a[0].to_s
                    e << t
                end
            end
        end
    end

    #--
    # Accepts XdX'X.X", XDXmX.XXs, XdXmX.XXs, or X.XXXX with either +/- or N/E/S/W
    #++
    def Kamelopard.convert_coord(a)    # :nodoc
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
    def Kamelopard.add_altitudeMode(mode, e)
        return if mode.nil?
        if mode == :clampToGround or mode == :relativeToGround or mode == :absolute then
            t = XML::Node.new 'altitudeMode'
        else
            t = XML::Node.new 'gx:altitudeMode'
        end
        t << mode.to_s
        e << t
    end

    # Base class for all Kamelopard objects. Manages object ID and a single
    # comment string associated with the object
    class Object
        attr_accessor :obj_id, :comment

        def initialize(comment = nil)
            @obj_id = "#{self.class.name.gsub('Kamelopard::', '')}_#{ Kamelopard.get_next_id }"
            @comment = comment.gsub(/</, '&lt;') unless comment.nil?
        end

        # Returns KML string for this object. Objects should override this method
        def to_kml(elem)
            elem.attributes['id'] = @obj_id
            if not @comment.nil? and @comment != '' then
                c = XML::Node.new_comment " #{@comment} "
                elem << c
                return c
            end
        end
    end

    # Abstract base class for Point and several other classes
    class Geometry < Object
    end

    # Represents a Point in KML.
    class Point < Geometry
        attr_accessor :longitude, :latitude, :altitude, :altitudeMode, :extrude
        def initialize(long, lat, alt=0, altmode=:clampToGround, extrude=false)
            super()
            @longitude = Kamelopard.convert_coord(long)
            @latitude = Kamelopard.convert_coord(lat)
            @altitude = alt
            @altitudeMode = altmode
            @extrude = extrude
        end

        def to_s
            "Point (#{@longitude}, #{@latitude}, #{@altitude}, mode = #{@altitudeMode}, #{ @extrude ? 'extruded' : 'not extruded' })"
        end

        def to_kml(elem = nil, short = false)
            e = XML::Node.new 'Point'
            super(e)
            e.attributes['id'] = @obj_id
            c = XML::Node.new 'coordinates'
            c << "#{ @longitude }, #{ @latitude }, #{ @altitude }"
            e << c

            if not short then
                c = XML::Node.new 'extrude'
                c << ( @extrude ? 1 : 0 ).to_s
                e << c

                Kamelopard.add_altitudeMode(@altitudeMode, e)
            end

            elem << e unless elem.nil?
            e
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
            e = XML::Node.new 'coordinates'
            t = ''
            @coordinates.each do |a|
                t << "#{ a[0] },#{ a[1] }"
                t << ",#{ a[2] }" if a.size > 2
                t << ' '
            end
            e << t.chomp(' ')
            elem << e unless elem.nil?
            e
        end

        # Alias for add_element
        def <<(a)
            add_element a
        end

        # Adds one or more elements to this CoordinateList. The argument can be in any of several formats:
        # * An array of arrays of numeric objects, in the form [ longitude,
        #   latitude, altitude (optional) ]
        # * A Point, or some other object that response to latitude, longitude, and altitude methods
        # * An array of the above
        # * Another CoordinateList, to append to this on
        # Note that this will not accept a one-dimensional array of numbers to add
        # a single point. Instead, create a Point with those numbers, and pass
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
            k = XML::Node.new 'LineString'
            super(k)
            Kamelopard.kml_array(k, [
                [@altitudeOffset, 'gx:altitudeOffset'],
                [@extrude, 'extrude'],
                [@tessellate, 'tessellate'],
                [@drawOrder, 'gx:drawOrder']
            ])
            @coordinates.to_kml(k) unless @coordinates.nil?
            Kamelopard.add_altitudeMode @altitudeMode, k
            elem << k unless elem.nil?
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
            k = XML::Node.new 'LinearRing'
            super(k)
            Kamelopard.kml_array(k, [
                [ @altitudeOffset, 'gx:altitudeOffset' ],
                [ @tessellate, 'tessellate' ],
                [ @extrude, 'extrude' ]
            ])
            Kamelopard.add_altitudeMode(@altitudeMode, k)
            @coordinates.to_kml(k)
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to KML's AbstractView object
    class AbstractView < Object
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
                @point = Point.new(a, 0)
            else
                @point.longitude = a
            end
        end

        def latitude=(a)
            if @point.nil? then
                @point = Point.new(0, a)
            else
                @point.latitude = a
            end
        end

        def altitude=(a)
            if @point.nil? then
                @point = Point.new(0, 0, a)
            else
                @point.altitude = a
            end
        end

        def to_kml(elem = nil)
            t = XML::Node.new @className
            super(t)
            Kamelopard.kml_array(t, [
                [ @point.nil? ? nil : @point.longitude, 'longitude' ],
                [ @point.nil? ? nil : @point.latitude, 'latitude' ],
                [ @point.nil? ? nil : @point.altitude, 'altitude' ],
                [ @heading, 'heading' ],
                [ @tilt, 'tilt' ],
                [ @range, 'range' ],
                [ @roll, 'roll' ]
            ])
            Kamelopard.add_altitudeMode(@altitudeMode, t)
            if @options.keys.length > 0 then
                vo = XML::Node.new 'gx:ViewerOptions'
                @options.each do |k, v|
                    o = XML::Node.new 'gx:option'
                    o.attributes['name'] = k.to_s
                    o.attributes['enabled'] = v ? 'true' : 'false'
                    vo << o
                end
                t << vo
            end
            if not @timestamp.nil? then
                @timestamp.to_kml(t, 'gx')
            elsif not @timespan.nil? then
                @timespan.to_kml(t, 'gx')
            end
            elem << t unless elem.nil?
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
    class TimePrimitive < Object
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

            k = XML::Node.new "#{prefix}TimeStamp"
            super(k)
            w = XML::Node.new 'when'
            w << @when
            k << w
            elem << k unless elem.nil?
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

            k = XML::Node.new "#{prefix}TimeSpan"
            super(k)
            if not @begin.nil? then
                w = XML::Node.new 'begin'
                w << @begin
                k << w
            end
            if not @end.nil? then
                w = XML::Node.new 'end'
                w << @end
                k << w
                elem << k unless elem.nil?
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
            e = XML::Node.new 'Snippet'
            e.attributes['maxLines'] = @maxLines.to_s
            e << @text
            elem << e unless elem.nil?
            e
        end
    end

    # Abstract class corresponding to KML's Feature object.
    class Feature < Object
        # Abatract class
        attr_accessor :visibility, :open, :atom_author, :atom_link, :name,
            :phoneNumber, :description, :abstractView,
            :timeprimitive, :styleUrl, :styleSelector, :region, :metadata,
            :extendedData, :styles
        attr_reader :addressDetails, :snippet

        def initialize (name = nil)
            super()
            @name = name
            @visibility = true
            @open = false
            @styles = []
        end

        def snippet=(a)
            if a.is_a? String then
                @snippet = Kamelopard::Snippet.new a
            else
                @snippet = a
            end
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
        # containing the desired StyleSelector's @obj_id
        def styleUrl=(a)
            if a.is_a? String then
                @styleUrl = a
            elsif a.respond_to? 'id' then
                @styleUrl = "##{ a.obj_id }"
            else
                @styleUrl = a.to_s
            end
        end

        def self.add_author(o, a)
            e = XML::Node.new 'atom:name'
            e << a.to_s
            f = XML::Node.new 'atom:author'
            f << e
            o << f
        end

        def to_kml(elem = nil)
            elem = XML::Node.new 'Feature' if elem.nil?
            super(elem)
            Kamelopard.kml_array(elem, [
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
            h = XML::Node.new 'Folder'
            super h
            @features.each do |a|
                a.to_kml(h)
            end
            @folders.each do |a|
                a.to_kml(h)
            end
            elem << h unless elem.nil?
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
            Tour.new if @tours.length == 0
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
            k = XML::Document.new
            # XXX fix this
            #k << XML::XMLDecl.default
            k.root = XML::Node.new('kml')
            r = k.root
            if @uses_xal then
                r.attributes['xmlns:xal'] = "urn:oasis:names:tc:ciq:xsdschema:xAL:2.0"
            end
    # XXX Should this be add_namespace instead?
            r.attributes['xmlns'] = 'http://www.opengis.net/kml/2.2'
            r.attributes['xmlns:gx'] = 'http://www.google.com/kml/ext/2.2'
            r.attributes['xmlns:kml'] = 'http://www.opengis.net/kml/2.2'
            r.attributes['xmlns:atom'] = 'http://www.w3.org/2005/Atom'
            r << self.to_kml
            k
        end

        def to_kml
            d = XML::Node.new 'Document'
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
    class ColorStyle < Object
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
            k = elem.nil? ? XML::Node.new('ColorStyle') : elem
            super k
            e = XML::Node.new 'color'
            e << @color
            k << e
            e = XML::Node.new 'colorMode'
            e << @colorMode
            k << e
            k
        end
    end

    # Corresponds to KML's BalloonStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class BalloonStyle < Object
        attr_accessor :bgColor, :text, :textColor, :displayMode

        # Note: color element order is aabbggrr
        def initialize(text = '', textColor = 'ff000000', bgColor = 'ffffffff', displayMode = :default)
            super()
            @bgColor = bgColor
            @text = text
            @textColor = textColor
            @displayMode = displayMode
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'BalloonStyle'
            super k
            Kamelopard.kml_array(k, [
                [ @bgColor, 'bgColor' ],
                [ @text, 'text' ],
                [ @textColor, 'textColor' ],
                [ @displayMode, 'displayMode' ]
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Internal class used where KML requires X and Y values and units
    class XY
        attr_accessor :x, :y, :xunits, :yunits
        def initialize(x = 0.5, y = 0.5, xunits = :fraction, yunits = :fraction)
            @x = x
            @y = y
            @xunits = xunits
            @yunits = yunits
        end

        def to_kml(name, elem = nil)
            k = XML::Node.new name
            k.attributes['x'] = @x.to_s
            k.attributes['y'] = @y.to_s
            k.attributes['xunits'] = @xunits.to_s
            k.attributes['yunits'] = @yunits.to_s
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to the KML Icon object
    class Icon
        attr_accessor :obj_id, :href, :x, :y, :w, :h, :refreshMode, :refreshInterval, :viewRefreshMode, :viewRefreshTime, :viewBoundScale, :viewFormat, :httpQuery

        def initialize(href = nil)
            @href = href
            @obj_id = "Icon_#{ Kamelopard.get_next_id }"
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Icon'
            k.attributes['id'] = @obj_id
            Kamelopard.kml_array(k, [
                [@href, 'href'],
                [@x, 'gx:x'],
                [@y, 'gx:y'],
                [@w, 'gx:w'],
                [@h, 'gx:h'],
                [@refreshMode, 'refreshMode'],
                [@refreshInterval, 'refreshInterval'],
                [@viewRefreshMode, 'viewRefreshMode'],
                [@viewRefreshTime, 'viewRefreshTime'],
                [@viewBoundScale, 'viewBoundScale'],
                [@viewFormat, 'viewFormat'],
                [@httpQuery, 'httpQuery'],
            ])
            elem << k unless elem.nil?
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
            @hotspot = XY.new(hs_x, hs_y, hs_xunits, hs_yunits) unless (hs_x.nil? and hs_y.nil? and hs_xunits.nil? and hs_yunits.nil?)
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'IconStyle'
            super(k)
            Kamelopard.kml_array( k, [
                [ @scale, 'scale' ],
                [ @heading, 'heading' ]
            ])
            if not @hotspot.nil? then
                h = XML::Node.new 'hotSpot'
                h.attributes['x'] = @hotspot.x.to_s
                h.attributes['y'] = @hotspot.y.to_s
                h.attributes['xunits'] = @hotspot.xunits.to_s
                h.attributes['yunits'] = @hotspot.yunits.to_s
                k << h
            end
            @icon.to_kml(k) unless @icon.nil?
            elem << k unless elem.nil?
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
            k = XML::Node.new 'LabelStyle'
            super k
            s = XML::Node.new 'scale'
            s << @scale.to_s
            k << s
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's LineStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    class LineStyle < ColorStyle
        attr_accessor :outerColor, :outerWidth, :physicalWidth, :width

        def initialize(width = 1, outercolor = 'ffffffff', outerwidth = 0, physicalwidth = 0, color = 'ffffffff', colormode = :normal)
            super(color, colormode)
            @width = width
            @outerColor = outercolor
            @outerWidth = outerwidth
            @physicalWidth = physicalwidth
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'LineStyle'
            super k
            Kamelopard.kml_array(k, [
                [ @width, 'width' ],
                [ @outerColor, 'gx:outerColor' ],
                [ @outerWidth, 'gx:outerWidth' ],
                [ @physicalWidth, 'gx:physicalWidth' ],
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's ListStyle object. Color is stored as an 8-character hex
    # string, with two characters each of alpha, blue, green, and red values, in
    # that order, matching the ordering the KML spec demands.
    #--
    # This doesn't descend from ColorStyle because I don't want the to_kml()
    # call to super() adding color and colorMode elements to the KML -- Google
    # Earth complains about 'em
    #++
    class ListStyle < Object
        attr_accessor :listItemType, :bgColor, :state, :href

        def initialize(bgcolor = nil, state = nil, href = nil, listitemtype = nil)
            super()
            @bgcolor = bgcolor
            @state = state
            @href = href
            @listitemtype = listitemtype
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'ListStyle'

            super k
            Kamelopard.kml_array(k, [
                [@listitemtype, 'listItemType'],
                [@bgcolor, 'bgColor']
            ])
            if (! @state.nil? or ! @href.nil?) then
                i = XML::Node.new 'ItemIcon'
                Kamelopard.kml_array(i, [
                    [ @state, 'state' ],
                    [ @href, 'href' ]
                ])
                k << i
            end
            elem << k unless elem.nil?
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
            k = XML::Node.new 'PolyStyle'
            super k
            Kamelopard.kml_array( k, [
                [ @fill, 'fill' ],
                [ @outline, 'outline' ]
            ])
            elem << k unless elem.nil?
            k
        end
    end

    # Abstract class corresponding to KML's StyleSelector object.
    class StyleSelector < Object
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

        def to_kml(elem = nil)
            elem = XML::Node.new 'StyleSelector' if elem.nil?
            super elem
            elem
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
            k = XML::Node.new 'Style'
            super(k)
            @icon.to_kml(k) unless @icon.nil?
            @label.to_kml(k) unless @label.nil?
            @line.to_kml(k) unless @line.nil?
            @poly.to_kml(k) unless @poly.nil?
            @balloon.to_kml(k) unless @balloon.nil?
            @list.to_kml(k) unless @list.nil?
            elem << k unless elem.nil?
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
            @pairs.merge!(a)
        end

        def to_kml(elem = nil)
            t = XML::Node.new 'StyleMap'
            super t
            @pairs.each do |k, v|
                p = XML::Node.new 'Pair'
                key = XML::Node.new 'key'
                key << k.to_s
                p. << key
                if v.kind_of? Style then
                    v.to_kml(p)
                else
                    s = XML::Node.new 'styleUrl'
                    s << v.to_s
                    p << s
                end
                t << p
            end
            elem << t unless elem.nil?
            t
        end
    end

    # Corresponds to KML's Placemark objects. The geometry attribute requires a
    # descendant of Geometry
    class Placemark < Feature
        attr_accessor :name, :geometry
        def initialize(name = nil, geo = nil)
            super(name)
            # XXX FAIL... Placemarks should have 0 or 1 geometry elements. Use MultiGeometry for more
            @geometry = []
            self.geometry=(geo)
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Placemark'
            super k
            @geometry.each do |i| i.to_kml(k) unless i.nil? end
            elem << k unless elem.nil?
            k
        end

        def geometry=(geo)
            if geo.kind_of? Array then
                @geometry.concat geo
            else
                @geometry << geo
            end
        end

        def to_s
            "Placemark id #{ @obj_id } named #{ @name }"
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
            if @geometry[0].kind_of? Point then
                @geometry[0]
            else
                raise "This placemark uses a non-point geometry, but the operation you're trying requires a point object"
            end
        end
    end

    # Abstract class corresponding to KML's gx:TourPrimitive object. Tours are made up
    # of descendants of these.
    class TourPrimitive < Object
        def initialize
            Document.instance.tour << self
            super
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

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:FlyTo'
            super k
            Kamelopard.kml_array(k, [
                [ @duration, 'gx:duration' ],
                [ @mode, 'gx:flyToMode' ]
            ])
            @view.to_kml k unless @view.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's gx:AnimatedUpdate object. For now at least, this isn't very
    # intelligent; you've got to manually craft the <Change> tag(s) within the
    # object.
    class AnimatedUpdate < TourPrimitive
        # XXX For now, the user has to specify the change / create / delete elements in
        # the <Update> manually, rather than creating objects.
        attr_accessor :target, :delayedStart, :updates, :duration

        # The updates argument is an array of strings containing <Change> elements
        def initialize(updates = [], duration = 0, target = '', delayedstart = nil)
            super()
            begin
                raise "incorrect object type" unless @target.kind_of? Object
                @target = target.obj_id
            rescue RuntimeError
                @target = target
            end
            @updates = []
            updates.each do |u| self.<<(u) end
            @duration = duration
            @delayedStart = delayedstart
        end

        # Adds another update string, presumably containing a <Change> element
        def <<(a)
            @updates << a
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:AnimatedUpdate'
            super(k)
            d = XML::Node.new 'gx:duration'
            d << @duration.to_s
            k << d
            if not @delayedStart.nil? then
                d = XML::Node.new 'gx:delayedStart'
                d << @delayedStart.to_s
                k << d
            end
            d = XML::Node.new 'Update'
            q = XML::Node.new 'targetHref'
            q << @target.to_s
            d << q
            @updates.each do |i|
                parser = reader = XML::Parser.string(i)
                doc = parser.parse
                node = doc.child
                n = node.copy true
                d << n
            end
            k << d
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:TourControl object
    class TourControl < TourPrimitive
        def initialize
            super
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:TourControl'
            super(k)
            q = XML::Node.new 'gx:playMode'
            q << 'pause'
            k << q
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:Wait object
    class Wait < TourPrimitive
        attr_accessor :duration
        def initialize(duration = 0)
            super()
            @duration = duration
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:Wait'
            super k
            d = XML::Node.new 'gx:duration'
            d << @duration.to_s
            k << d
            elem << k unless elem.nil?
            k
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

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:SoundCue'
            super k
            d = XML::Node.new 'href'
            d << @href.to_s
            k << d
            if not @delayedStart.nil? then
                d = XML::Node.new 'gx:delayedStart'
                d << @delayedStart.to_s
                k << d
            end
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to a KML gx:Tour object
    class Tour < Object
        attr_accessor :name, :description, :last_abs_view
        def initialize(name = nil, description = nil)
            super()
            @name = name
            @description = description
            @items = []
            Document.instance.tours << self
        end

        # Add another element to this Tour
        def <<(a)
            @items << a
            @last_abs_view = a.view if a.kind_of? FlyTo
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:Tour'
            super k
            Kamelopard.kml_array(k, [
                [ @name, 'name' ],
                [ @description, 'description' ],
            ])
            p = XML::Node.new 'gx:Playlist'
            @items.map do |a| a.to_kml p end
            k << p
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

        def to_kml(elem)
            super
            Kamelopard.kml_array(elem, [
                [ @color, 'color' ],
                [ @drawOrder, 'drawOrder' ],
            ])
            @icon.to_kml(elem) unless @icon.nil?
            elem
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

        def to_kml(elem = nil)
            k = XML::Node.new 'ScreenOverlay'
            super k
            @overlayXY.to_kml('overlayXY', k)   unless @overlayXY.nil?
            @screenXY.to_kml('screenXY', k)     unless @screenXY.nil?
            @rotationXY.to_kml('rotationXY', k) unless @rotationXY.nil?
            if ! @size.nil? then
                s = XML::Node.new 'size'
                s << XML::Node.new_text(@size.to_s)
                k << s
            end
            if ! @rotation.nil? then
                d = XML::Node.new 'rotation'
                d << @rotation.to_s
                k << d
            end
            elem << k unless elem.nil?
            k
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

        def to_kml(elem = nil)
            p = XML::Node.new 'ViewVolume'
            {
                :near => @near,
                :leftFov => @leftFov,
                :rightFov => @rightFov,
                :topFov => @topFov,
                :bottomFov => @bottomFov
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
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

        def to_kml(elem = nil)
            p = XML::Node.new 'ImagePyramid'
            {
                :tileSize => @tileSize,
                :maxWidth => @maxWidth,
                :maxHeight => @maxHeight,
                :gridOrigin => @gridOrigin
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
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

        def to_kml(elem = nil)
            p = XML::Node.new 'PhotoOverlay'
            super p
            @viewVolume.to_kml p   unless @viewVolume.nil?
            @imagePyramid.to_kml p unless @imagePyramid.nil?
            p << @point.to_kml(nil, true)
            {
                :rotation => @rotation,
                :shape => @shape
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                p << d
            end
            elem << p unless elem.nil?
            p
        end
    end

    # Corresponds to KML's LatLonBox and LatLonAltBox
    class LatLonBox
        attr_reader :north, :south, :east, :west
        attr_accessor :rotation, :minAltitude, :maxAltitude, :altitudeMode

        def initialize(north, south, east, west, rotation = 0, minAltitude = nil, maxAltitude = nil, altitudeMode = :clampToGround)
            @north = Kamelopard.convert_coord north
            @south = Kamelopard.convert_coord south
            @east = Kamelopard.convert_coord east
            @west = Kamelopard.convert_coord west
            @minAltitude = minAltitude
            @maxAltitude = maxAltitude
            @altitudeMode = altitudeMode
            @rotation = rotation
        end

        def north=(a)
            @north = Kamelopard.convert_coord a
        end

        def south=(a)
            @south = Kamelopard.convert_coord a
        end

        def east=(a)
            @east = Kamelopard.convert_coord a
        end

        def west=(a)
            @west = Kamelopard.convert_coord a
        end

        def to_kml(elem = nil, alt = false)
            name = alt ? 'LatLonAltBox' : 'LatLonBox'
            k = XML::Node.new name
            [
                ['north', @north],
                ['south', @south],
                ['east', @east],
                ['west', @west],
                ['minAltitude', @minAltitude],
                ['maxAltitude', @maxAltitude]
            ].each do |a|
                if not a[1].nil? then
                    m = XML::Node.new a[0]
                    m << a[1].to_s
                    k << m
                end
            end
            if (not @minAltitude.nil? or not @maxAltitude.nil?) then
                Kamelopard.add_altitudeMode(@altitudeMode, k)
            end
            m = XML::Node.new 'rotation'
            m = @rotation.to_s
            k << m
            elem << k unless elem.nil?
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

        def to_kml(elem = nil)
            k = XML::Node.new 'gx:LatLonQuad'
            d = XML::Node.new 'coordinates'
            d << "#{ @lowerLeft.longitude },#{ @lowerLeft.latitude } #{ @lowerRight.longitude },#{ @lowerRight.latitude } #{ @upperRight.longitude },#{ @upperRight.latitude } #{ @upperLeft.longitude },#{ @upperLeft.latitude }"
            k << d
            elem << k unless elem.nil?
            k
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

        def to_kml(elem = nil)
            raise "Either latlonbox or latlonquad must be non-nil" if @latlonbox.nil? and @latlonquad.nil?
            k = XML::Node.new 'GroundOverlay'
            super k
            d = XML::Node.new 'altitude'
            d << @altitude.to_s
            k << d
            Kamelopard.add_altitudeMode(@altitudeMode, k)
            @latlonbox.to_kml(k) unless @latlonbox.nil?
            @latlonquad.to_kml(k) unless @latlonquad.nil?
            elem << k unless elem.nil?
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
            k = XML::Node.new 'Lod'
            m = XML::Node.new 'minLodPixels'
            m << @minpixels.to_s
            k << m
            m = XML::Node.new 'maxLodPixels'
            m << @maxpixels.to_s
            k << m
            m = XML::Node.new 'minFadeExtent'
            m << @minfade.to_s
            k << m
            m = XML::Node.new 'maxFadeExtent'
            m << @maxfade.to_s
            k << m
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to the KML Region object
    class Region < Object
        attr_accessor :latlonaltbox, :lod

        def initialize(latlonaltbox, lod)
            super()
            @latlonaltbox = latlonaltbox
            @lod = lod
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Region'
            super(k)
            @latlonaltbox.to_kml(k, true) unless @latlonaltbox.nil?
            @lod.to_kml(k) unless @lod.nil?
            elem << k unless elem.nil?
            k
        end
    end

    # Sub-object in the KML Model class
    class Orientation
        attr_accessor :heading, :tilt, :roll
        def initialize(heading, tilt, roll)
            @heading = heading
            # Although the KML reference by Google is clear on these ranges, Google Earth
            # supports values outside the ranges, and sometimes it's useful to use
            # them. So I'm turning off this error checking
            #raise "Heading should be between 0 and 360 inclusive; you gave #{ heading }" unless @heading <= 360 and @heading >= 0
            @tilt = tilt
            #raise "Tilt should be between 0 and 180 inclusive; you gave #{ tilt }" unless @tilt <= 180 and @tilt >= 0
            @roll = roll
            #raise "Roll should be between 0 and 180 inclusive; you gave #{ roll }" unless @roll <= 180 and @roll >= 0
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Orientation'
            {
                :heading => @heading,
                :tilt => @tilt,
                :roll => @roll
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
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

        def to_kml(elem = nil)
            x = XML::Node.new 'Scale'
            {
                :x => @x,
                :y => @y,
                :z => @z
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
        end
    end

    # Sub-object in the KML ResourceMap class
    class Alias
        attr_accessor :targetHref, :sourceHref
        def initialize(targetHref = nil, sourceHref = nil)
            @targetHref = targetHref
            @sourceHref = sourceHref
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Alias'
            {
                :targetHref => @targetHref,
                :sourceHref => @sourceHref,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            elem << x unless elem.nil?
            x
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

        def to_kml(elem = nil)
            k = XML::Node.new 'ResourceMap'
            @aliases.each do |a| k << a.to_kml(k) end
            elem << k unless elem.nil?
            k
        end
    end

    # Corresponds to KML's Link object
    class Link < Object
        attr_accessor :href, :refreshMode, :refreshInterval, :viewRefreshMode, :viewBoundScale, :viewFormat, :httpQuery
        def initialize(href = '', refreshMode = :onChange, viewRefreshMode = :never)
            super()
            @href = href
            @refreshMode = refreshMode
            @viewRefreshMode = viewRefreshMode
        end

        def to_kml(elem = nil)
            x = XML::Node.new 'Link'
            super x
            {
                :href => @href,
                :refreshMode => @refreshMode,
                :viewRefreshMode => @viewRefreshMode,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                x << d
            end
            Kamelopard.kml_array(x, [
                [ @refreshInterval, 'refreshInterval' ],
                [ @viewBoundScale, 'viewBoundScale' ],
                [ @viewFormat, 'viewFormat' ],
                [ @httpQuery, 'httpQuery' ]
            ])
            elem << x unless elem.nil?
            x
        end
    end

    # Corresponds to the KML Model class
    class Model < Geometry
        attr_accessor :link, :location, :orientation, :scale, :resourceMap

        # location should be a Point, or some object that can behave like one,
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

        def to_kml(elem = nil)
            x = XML::Node.new 'Model'
            super x
            loc = XML::Node.new 'Location'
            {
                :longitude => @location.longitude,
                :latitude => @location.latitude,
                :altitude => @location.altitude,
            }.each do |k, v|
                d = XML::Node.new k.to_s
                d << v.to_s
                loc << d
            end
            x << loc
            Kamelopard.add_altitudeMode(@location.altitudeMode, x)
            @link.to_kml x
            @orientation.to_kml x
            @scale.to_kml x
            @resourceMap.to_kml x
            elem << x unless elem.nil?
            x
        end
    end

    # Corresponds to the KML Polygon class
    class Polygon < Geometry
        # NB!  No support for tessellate, because Google Earth doesn't support it, it seems
        attr_accessor :outer, :inner, :altitudeMode, :extrude

        def initialize(outer, extrude = 0, altitudeMode = :clampToGround)
            super()
            @outer = outer
            @extrude = extrude
            @altitudeMode = altitudeMode
            @inner = []
        end

        def inner=(a)
            if a.kind_of? Array then
                @inner = a
            else
                @inner = [ a ]
            end
        end

        def <<(a)
            @inner << a
        end

        def to_kml(elem = nil)
            k = XML::Node.new 'Polygon'
            super k
            e = XML::Node.new 'extrude'
            e << @extrude.to_s
            k << e
            Kamelopard.add_altitudeMode @altitudeMode, k
            e = XML::Node.new('outerBoundaryIs')
            e << @outer.to_kml
            k << e
            @inner.each do |i|
                e = XML::Node.new('innerBoundaryIs')
                e << i.to_kml
                k << e
            end
            elem << k unless elem.nil?
            k
        end
    end

    class MultiGeometry < Geometry
        attr_accessor :geometries

        def initialize(a = nil)
            @geometries = []
            @geometries << a unless a.nil?
        end

        def <<(a)
            @geometries << a
        end

        def to_kml(elem = nil)
            e = XML::Node.new 'MultiGeometry'
            @geometries.each do |g|
                g.to_kml e
            end
            elem << e unless elem.nil?
            e
        end
    end

    class NetworkLink < Feature
        attr_accessor :refreshVisibility, :flyToView, :link

        def initialize(href = '', refreshMode = :onChange, viewRefreshMode = :never)
            super()
            @link = Link.new(href, refreshMode, viewRefreshMode)
            @refreshVisibility = 0
            @flyToView = 0
        end

        def refreshMode
            link.refreshMode
        end

        def viewRefreshMode
            link.viewRefreshMode
        end

        def href
            link.href
        end

        def refreshMode=(a)
            link.refreshMode = a
        end

        def viewRefreshMode=(a)
            link.viewRefreshMode = a
        end

        def href=(a)
            link.href = a
        end

        def to_kml(elem = nil)
            e = XML::Node.new 'NetworkLink'
            super e
            @link.to_kml e
            Kamelopard.kml_array(e, [
                [@flyToView, 'flyToView'],
                [@refreshVisibility, 'refreshVisibility']
            ])
            elem << e unless elem.nil?
            e
        end
    end

end
# End of Kamelopard module
