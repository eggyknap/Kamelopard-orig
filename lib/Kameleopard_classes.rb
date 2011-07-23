require 'singleton'

@@sequence = 0

def get_next_id
    @@sequence += 1
    @@sequence
end

# Print out a set of kml fields. Expects an array argument. Each entry in the
# array is itself an array, containing two strings and a boolean. If the first
# string is nil, the function won't print anything for that element. If it's
# not null, it consults the boolean. True values tell the function to treat the
# second string as a KML element name, and print it along with XML decorators
# and the field value. False values mean just print the second string, with no
# decorators and no other values
def kml_array(m, indent = 0)
    k = ''
    m.map do |a|
        r = ''
        if ! a[0].nil? then
            if a[2] then
                r << "#{ ' ' * indent}<" << a[1] << '>' << a[0].to_s << '</' << a[1] << ">\n"
            else
                r << a[1] << "\n"
            end
        end
        k << r
    end
    k
end

# Accepts XdX'X.X" or X.XXXX with either +/- or N/E/S/W
def convert_coord(a)
    # XXX Make sure coordinate is valid for the type of coordinate the caller wants, based on some other value passed in
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
    elsif a =~ /^\d+D\d+'\d+(\.\d+)?"$/ then
        # coord is in d'"
        p = a.split /[D"']/
        a = p[0].to_f + (p[2].to_f / 60.0 + p[1].to_f) / 60.0
    else
        raise "Couldn't determine coordinate format for #{a}"
    end

    # check that it's within range
    a = a.to_f * mult
    a -= 180 if a > 180
    a += 180 if a < -180
    return a
end

class KMLObject
    attr_reader :id

    def initialize
        @id = "#{self.class.name}_#{ get_next_id }"
    end

    def to_kml(indent = 0)
        raise "to_kml for this object (#{ self }) isn't yet defined!"
    end
end

class Geometry < KMLObject
end

class Point < Geometry
    attr_accessor :id, :longitude, :latitude, :altitude, :altitudeMode, :extrude
    def initialize(long, lat, alt=0, altmode=:clampToGround, extrude=false)
        super()
        @longitude = convert_coord(long)
        @latitude = convert_coord(lat)
        @altitude = alt
        @altitudeMode = altmode
        @extrude = extrude
    end

    def to_s
        "Point (#{@longitude}, #{@latitude}, #{@altitude}, mode = #{@altitudeMode}, #{ @extrude ? 'extruded' : 'not extruded' })"
    end

    def to_kml(indent = 0)

        <<-point_kml
#{ ' ' * indent }<Point id="#{ @id }">
#{ ' ' * indent }    <extrude>#{ @extrude ? 1 : 0 }</extrude>
#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>
#{ ' ' * indent }    <coordinates>#{ @longitude }, #{ @latitude }, #{ @altitude }</coordinates>
#{ ' ' * indent }</Point>
        point_kml
    end
end

class AbstractView < KMLObject
end

class Camera < AbstractView
end

class LookAt < AbstractView
    attr_accessor :longitude, :latitude, :altitude, :heading, :tilt, :range, :altitudeMode
    def initialize(point = nil, heading = 0, tilt = 0, range = 0)
        super()
        if point.nil? then
            @point = nil
        elsif point.kind_of? Placemark then
            @point = point.point
        else
            @point = point
        end
        @heading = heading
        @tilt = tilt
        @range = range
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<LookAt id=\"#{@id}\">\n"
        # XXX Need to include AbstractView stuff here sometime
        k << kml_array([
            [ @point.longitude, 'longitude', true ],
            [ @point.latitude, 'latitude', true ],
            [ @point.altitude, 'altitude', true ],
            [ @point.altitudeMode, 'altitudeMode', true ],
            [ @heading, 'heading', true ],
            [ @tilt, 'tilt', true ],
            [ @range, 'range', true ]
        ], indent + 4)
        k << "#{ ' ' * indent }</LookAt>\n"
    end
end

class Feature < KMLObject
    # Abstract class
    attr_accessor :visibility, :open, :atom_author, :atom_link, :name,
        :addressdetails, :phonenumber, :snippet, :description, :abstractview,
        :timeprimitive, :styleurl, :styleselector, :region, :metadata,
        :extendeddata

    def initialize (name = nil)
        super()
        @name = name
        @visibility = true
        @open = false
    end

    def to_kml(indent = 0)
        k = kml_array [
                [@name, 'name', true],
                [(@visibility.nil? || @visibility) ? 1 : 0, 'visibility', true],
                [(@open.nil? || ! @open) ? 1 : 0, 'open', true],
                [@atom_author, "<atom:author><atom:name>#{ @atom_author }</atom:name></atom:author>", false],
                [@atom_link, 'atom:link', true],
                [@address, 'address', true],
                [@addressdetails, 'xal:AddressDetails', false],   # XXX
                [@phonenumber, 'phoneNumber', true],
                [@snippet, 'Snippet', true],
                [@description, 'description', true],
                [@abstractview, 'abstractview', false ],          # XXX
                [@timeprimitive, 'timeprimitive', false ],        # XXX
                [@styleurl, 'styleUrl', true],
                [@styleselector, "<styleSelector>#{@styleselector.nil? ? '' : @styleselector.to_kml}</styleSelector>", false ],
                [@region, 'Region', false ],                      # XXX
                [@metadata, 'Metadata', false ],                  # XXX
                [@extendeddata, 'ExtendedData', false ]           # XXX
            ], (indent)
        k << yield if block_given?
        k
    end
end

class Container < Feature
    def initialize
        super
        @features = []
    end

    def <<(a)
        @features << a
    end
end

class Folder < Container
    def to_kml(indent = 0)
        h = "#{ ' ' * indent }<Folder id=\"#{@id}\">\n"
        h << super
        @features.each do |a|
            h << a.to_kml(indent + 4)
        end
        h << "#{ ' ' * indent }</Folder>\n";
        h
    end
end

class Document < Container
    include Singleton
    attr_accessor :flyto_mode, :folders, :tours, :styles, :spline_type, :spline_step

    def initialize
        @tours = []
        @folders = []
        @styles = []
        @spline_type = GSL::Interp::LINEAR
        @spline_step = .1
    end

    def tour
        @tours << Tour.new if @tours.length == 0
        @tours.last
    end

    def folder
        @folders << Folder.new if @folders.size == 0
        @folders.last
    end

    def to_kml
        h = <<-doc_header
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
        doc_header

        # Print styles first
        @styles.map do |a| h << a.to_kml(4) end

        # then folders
        @folders.map do |a| h << a.to_kml(4) end

        # then tours
        @tours.map do |a| h << a.to_kml(4) end
        h << "</Document>\n</kml>\n"

        h
    end
end

class ColorStyle < KMLObject
    attr_accessor :color
    attr_reader :colormode
    
    def initialize(color, colormode = :normal)
        super()
        # Note: color element order is aabbggrr
        @color = color
        check_colormode colormode
        @colormode = colormode # Can be :normal or :random
    end

    def check_colormode(a)
        raise "colorMode must be either \"normal\" or \"random\"" unless a == :normal or a == :random
    end

    def colormode=(a)
        check_colormode a
        @colormode = a
    end

    def alpha
        @color[0,1]
    end

    def alpha=(a)
        @color[0,1] = a
    end

    def blue
        @color[2,1]
    end

    def blue=(a)
        @color[2,1] = a
    end

    def green
        @color[4,1]
    end

    def green=(a)
        @color[4,1] = a
    end

    def red
        @color[6,1]
    end

    def red=(a)
        @color[6,1] = a
    end

    def to_kml(indent = 0)

        <<-colorstyle
#{ ' ' * indent }<color>#{@color}</color>
#{ ' ' * indent }<colorMode>#{@colormode}</colorMode>
        colorstyle
    end
end

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

    def to_kml(indent = 0)

        <<-balloonstyle
#{ ' ' * indent }<BalloonStyle id="#{@id}">
#{ ' ' * indent }    <bgColor>#{@bgcolor}</bgColor>
#{ ' ' * indent }    <text>#{@text}</text>
#{ ' ' * indent }    <textColor>#{@textcolor}</textColor>
#{ ' ' * indent }    <displayMode>#{@displaymode}</displayMode>
#{ ' ' * indent }</BalloonStyle>
        balloonstyle
    end
end

class IconStyle < ColorStyle
    attr_accessor :scale, :heading, :href, :hs_x, :hs_y, :hs_xunits, :hs_yunits

    def initialize(href, scale = 1, heading = 0, hs_x = 0.5, hs_y = 0.5, hs_xunits = :fraction, hs_yunits = :fraction, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @href = href
        @scale = scale
        @heading = heading
        @hs_x = hs_x
        @hs_y = hs_y
        @hs_xunits = hs_xunits
        @hs_yunits = hs_yunits
    end

    def to_kml(indent = 0)

        <<-iconstyle
#{ ' ' * indent }<IconStyle id="#{@id}">
#{ super(indent + 4) }
#{ ' ' * indent }    <scale>#{@scale}</scale>
#{ ' ' * indent }    <heading>#{@heading}</heading>
#{ ' ' * indent }    <Icon>
#{ ' ' * indent }        <href>#{@href}</href>
#{ ' ' * indent }    </Icon>
#{ ' ' * indent }    <hotSpot x="#{@hs_x}" y="#{@hs_y}" xunits="#{@hs_xunits}" yunits="#{@hs_yunits}" />
#{ ' ' * indent }</IconStyle>
        iconstyle
    end
end

class LabelStyle < ColorStyle
    attr_accessor :scale

    def initialize(scale = 1, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @scale = scale
    end

    def to_kml(indent = 0)

        <<-labelstyle
#{ ' ' * indent }<LabelStyle id="#{@id}">
#{ super(indent + 4) }
#{ ' ' * indent }    <scale>#{@scale}</scale>
#{ ' ' * indent }</LabelStyle>
        labelstyle
    end
end

class LineStyle < ColorStyle
    attr_accessor :outercolor, :outerwidth, :physicalwidth, :width

    def initialize(width = 1, outercolor = 'ffffffff', outerwidth = 0, physicalwidth = 0, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @width = width
        @outercolor = outercolor
        @outerwidth = outerwidth
        @physicalwidth = physicalwidth
    end

    def to_kml(indent = 0)

        <<-linestyle
#{ ' ' * indent }<LineStyle id="#{@id}">
#{ super(indent + 4) }
#{ ' ' * indent }    <width>#{@width}</width>
#{ ' ' * indent }    <gx:outerColor>#{@outercolor}</gx:outerColor>
#{ ' ' * indent }    <gx:outerWidth>#{@outerwidth}</gx:outerWidth>
#{ ' ' * indent }    <gx:physicalWidth>#{@physicalwidth}</gx:physicalWidth>
#{ ' ' * indent }</LineStyle>
        linestyle
    end
end

class ListStyle < ColorStyle
    attr_accessor :listitemtype, :bgcolor, :state, :href

    def initialize(bgcolor = nil, state = nil, href = nil, listitemtype = nil)
        super(nil, :normal)
        @bgcolor = bgcolor
        @state = state
        @href = href
        @listitemtype = listitemtype
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<ListStyle id=\"#{@id}\">\n"
        k << kml_array([
            [@listitemtype, 'listItemType', true],
            [@bgcolor, 'bgColor', true]
        ], indent + 4)
        if (! @state.nil? or ! @href.nil?) then
            k << "#{ ' ' * indent }    <ItemIcon>\n"
            k << "#{ ' ' * indent }        <state>#{@state}</state>\n" unless @state.nil? 
            k << "#{ ' ' * indent }        <href>#{@href}</href>\n" unless @href.nil? 
            k << "#{ ' ' * indent }    </ItemIcon>\n"
        end
        k << "#{ ' ' * indent }</ListStyle>\n"
        k
    end
end

class PolyStyle < ColorStyle
    attr_accessor :fill, :outline

    def initialize(fill = 1, outline = 1, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @fill = fill
        @outline = outline
    end

    def to_kml(indent = 0)

        <<-polystyle
#{ ' ' * indent }<PolyStyle id="#{@id}">
#{ super(indent + 4) }
#{ ' ' * indent }    <fill>#{@fill}</fill>
#{ ' ' * indent }    <outline>#{@outline}</outline>
#{ ' ' * indent }</PolyStyle>
        polystyle
    end
end

class StyleSelector < KMLObject
    def initialize
        super
        Document.instance.styles << self
    end
end

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

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Style id=\"#{@id}\">\n"
        k << @icon.to_kml(indent + 4) unless @icon.nil?
        k << @label.to_kml(indent + 4) unless @label.nil?
        k << @line.to_kml(indent + 4) unless @line.nil?
        k << @poly.to_kml(indent + 4) unless @poly.nil?
        k << @balloon.to_kml(indent + 4) unless @balloon.nil?
        k << @list.to_kml(indent + 4) unless @list.nil?
        k << "#{ ' ' * indent }</Style>\n"
        k
    end
end

class StyleMap < StyleSelector
    # StyleMap manages pairs. The first entry in each pair is a string key, the
    # second is either a Style or a styleUrl. It will be assumed to be the
    # latter if its kind_of? method doesn't claim it's a Style object
    def initialize(pairs = {})
        super()
        @pairs = []
        pairs.each do |k, v|
            self << [k, v]
        end
    end

    def <<(a)
        id = get_next_id
        @pairs << [id, a[0], a[1]]
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<StyleMap id=\"#{@id}\">\n"
        @pairs.each do |a|
            k << "#{ ' ' * indent }    <Pair id=\"Pair_#{ a[0] }\">\n"
            k << "#{ ' ' * indent }        <key>#{ a[1] }</key>\n"
            if a[2].kind_of? Style then
                k << "#{ ' ' * indent }    " << a[2].to_kml
            else
                k << "#{ ' ' * indent }    <styleUrl>#{ a[2] }</styleUrl>\n"
            end
            k << "#{ ' ' * indent }    </Pair>\n"
        end
        k << "#{ ' ' * indent }</StyleMap>\n"
    end
end

class Placemark < Feature
    attr_accessor :name, :geometry
    def initialize(name = nil, geo = nil)
        super(name)
        Document.instance.folder << self
        @geometry = geo
    end
    
    def to_kml(indent = 0)
        a = "#{ ' ' * indent }<Placemark id=\"#{ @id }\">\n"
        a << super(indent + 4) {
            @geometry.nil? ? '' : @geometry.to_kml(indent + 4)
        }
        a << "#{ ' ' * indent }</Placemark>\n"
    end

    def point
        if @geometry.kind_of? Point then
            @geometry
        else
            raise "This placemark uses a non-point geometry, but the operation you're trying requires a point object"
        end
    end
end

class TourPrimitive < KMLObject
    def initialize
        Document.instance.tour << self
    end
end

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
        @view.range = range unless range.nil?
        super()
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<gx:FlyTo>\n"
        k << kml_array([
            [ @duration, 'gx:duration', true ],
            [ @mode, 'gx:flyToMode', true ]
        ], indent + 4)
        k << @view.to_kml(indent + 4) unless @view.nil?
        k << "#{ ' ' * indent }</gx:FlyTo>\n"
    end
end

class AnimatedUpdate < TourPrimitive
    # For now, the user has to specify the change / create / delete elements in
    # the <Update> manually, rather than creating objects.
    attr_accessor :target, :delayedstart, :updates, :duration

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

    def <<(a)
        @updates << a << "\n"
    end

    def to_kml(indent = 0)
        k = <<-animatedupdate_kml
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

class TourControl < TourPrimitive
end

class Wait < TourPrimitive
    attr_accessor :duration
    def initialize(duration = 0)
        super()
        @duration = duration
    end

    def to_kml(indent = 0)

        <<-wait_kml
#{ ' ' * indent }<gx:Wait><gx:duration>#{@duration}</gx:duration></gx:Wait>
        wait_kml
    end
end

class SoundCue < TourPrimitive
end

class Tour < KMLObject
    attr_accessor :name, :description, :last_abs_view
    def initialize(name = nil, description = nil)
        super()
        @name = name
        @description = description
        @items = []
    end

    # Add another element to a tour
    def <<(a)
        @items << a
        @last_abs_view = a.view if a.kind_of? FlyTo
    end

    def to_kml(indent = 0)

        k = "#{ ' ' * indent }<gx:Tour id=\"#{ @id }\">\n"
        k << kml_array([
            [ @name, 'name', true ],
            [ @description, 'description', true ],
        ], indent + 4)
        k << "#{ ' ' * indent }    <gx:Playlist>\n";

        @items.map do |a| k << a.to_kml(indent + 8) << "\n" end

        k << "#{ ' ' * indent }    </gx:Playlist>\n"
        k << "#{ ' ' * indent }</gx:Tour>\n"
        k
    end
end

class NDPointList
# Contains X lists of equal length
    def initialize(num)
        @size = num
        @lists = []
        (i..num).each do |i|
            @lists[i] = []
        end
    end

    def <<(a)
        # XXX I wonder what's easier for people... we can
        #   1. Send this an array of arrays, where each inner array has one element for each list in @lists
        #   2. Send a one-dimensional array, with an element for @lists[1], then one for @lists[2], and so on
        #   3. Send an array of arrays, where the outer array's size is @size,
        #      and append one of the arrays to each array in @lists
        # For now I'll go with #3
        (0..@size).each do |i|
            @lists[i] << a[i]
        end
    end

    def x
        if @size >= 1 then
            return @lists[1]
        else
            raise "NDPointList of size #{@size} has no X element"
        end
    end

    def y
        if @size >= 2 then
            return @lists[2]
        else
            raise "NDPointList of size #{@size} has no Y element"
        end
    end

    def z
        if @size >= 3 then
            return @lists[3]
        else
            raise "NDPointList of size #{@size} has no Z element"
        end
    end

    def interpolate(type = nil, resolution = nil)
        vs = @lists.collect { |v| GSL::Interp.alloc(v) }
    end
end

class OneDPointList < NDPointList
    def initialize
        super 1
    end
end

class TwoDPointList < NDPointList
    def initialize
        super 2
    end
end

class ThreeDPointList < NDPointList
    def initialize
        super 3
    end
end

