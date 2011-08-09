# vim:ts=4:sw=4:et:smartindent:nowrap

# XXX add some geocoding feature
require 'singleton'
require 'Kameleopard_pointlist'

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
    attr_accessor :comment

    def initialize(comment = nil)
        @id = "#{self.class.name}_#{ get_next_id }"
        @comment = comment.gsub(/</, '&lt;') unless comment.nil?
    end

    def to_kml(indent = 0)
        if @comment.nil? or @comment == '' then
            ''
        else
            "#{ ' ' * indent }<!-- #{ @comment } -->\n"
        end
    end
end

class Geometry < KMLObject
end

class KMLPoint < Geometry
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
        "KMLPoint (#{@longitude}, #{@latitude}, #{@altitude}, mode = #{@altitudeMode}, #{ @extrude ? 'extruded' : 'not extruded' })"
    end

    def to_kml(indent = 0, short = false)
        # The short form includes only the coordinates tag
        k = super(indent + 4) + "#{ ' ' * indent }<Point id=\"#{ @id }\">\n"
        k << "#{ ' ' * indent }    <extrude>#{ @extrude ? 1 : 0 }</extrude>\n" unless short
        if not short then
            if @altitudeMode == :clampToGround or @altitudeMode == :absolute then
                k << "#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>\n"
            else
                k << "#{ ' ' * indent }    <gx:altitudeMode>#{ @altitudeMode }</gx:altitudeMode>\n"
            end
        end
        k << "#{ ' ' * indent }    <coordinates>#{ @longitude }, #{ @latitude }, #{ @altitude }</coordinates>\n"
        k << "#{ ' ' * indent }</Point>\n"
        k
    end
end

class AbstractView < KMLObject
    attr_accessor :timestamp, :timespan

    def to_kml(indent = 0)
#   XXX
#  <gx:ViewerOptions>
#    <option> name=" " type="boolean">     <!-- name="streetview", "historicalimagery", "sunlight", or "groundnavigation" -->
#    </option>
#  </gx:ViewerOptions>
        if not @timestamp.nil? then
            @timestamp.to_kml(indent+4, 'gx')
        elsif not @timespan.nil? then
            @timespan.to_kml(indent+4, 'gx')
        else
            ''
        end
    end
end

class Camera < AbstractView
    attr_accessor :longitude, :latitude, :altitude, :heading, :tilt, :roll, :altitudeMode
    def initialize(long = 0, lat = 0, alt = 0, heading = 0, tilt = 0, roll = 0, mode = :clampToGround)
        super()
        @longitude = long
        @latitude = lat
        @altitude = alt
        @heading = heading
        @tilt = tilt
        @roll = roll
        @altitudeMode = mode
    end

    def point=(point)
        @longitude = point.longitude
        @latitude = point.latitude
        @altitude = point.altitude
    end

    def to_kml(indent = 0)

        k = "#{ ' ' * indent }<Camera id=\"#{ @id }\">\n"
        k << super(indent)
        k << <<-camera
#{ ' ' * indent }    <longitude>#{ @longitude }</longitude>
#{ ' ' * indent }    <latitude>#{ @latitude }</latitude>
#{ ' ' * indent }    <altitude>#{ @altitude }</altitude>
#{ ' ' * indent }    <heading>#{ @heading }</heading>
#{ ' ' * indent }    <roll>#{ @roll }</roll>
#{ ' ' * indent }    <tilt>#{ @tilt }</tilt>
        camera
        if @altitudeMode == :clampToGround or @altitudeMode == :absolute then
            k << "#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>\n"
        else
            k << "#{ ' ' * indent }    <gx:altitudeMode>#{ @altitudeMode }</gx:altitudeMode>\n"
        end
        k << "#{ ' ' * indent }</Camera>\n"
    end
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
        k << super
        k << kml_array([
            [ @point.longitude, 'longitude', true ],
            [ @point.latitude, 'latitude', true ],
            [ @point.altitude, 'altitude', true ],
            [ @heading, 'heading', true ],
            [ @tilt, 'tilt', true ],
            [ @range, 'range', true ]
        ], indent + 4)
        if @altitudeMode == :clampToGround or @altitudeMode == :absolute then
            k << "#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>\n"
        else
            k << "#{ ' ' * indent }    <gx:altitudeMode>#{ @altitudeMode }</gx:altitudeMode>\n"
        end
        k << "#{ ' ' * indent }</LookAt>\n"
    end
end

class TimePrimitive < KMLObject
end

class TimeStamp < TimePrimitive
    attr_accessor :when
    def initialize(t_when)
        super()
        @when = t_when
    end

    def to_kml(indent = 0, ns = nil)
        prefix = ''
        prefix = ns + ':' unless ns.nil?
        
        <<-timestamp
#{ ' ' * indent }<#{ prefix }TimeStamp id="#{ @id }">
#{ ' ' * indent }    <when>#{ @when }</when>
#{ ' ' * indent }</#{ prefix }TimeStamp>
        timestamp
    end
end

class TimeSpan < TimePrimitive
    attr_accessor :begin, :end
    def initialize(t_begin, t_end)
        super()
        @begin = t_begin
        @end = t_end
    end

    def to_kml(indent = 0, ns = nil)
        prefix = ''
        prefix = ns + ':' unless ns.nil?

        k = "#{ ' ' * indent }<#{ prefix }TimeSpan id=\"#{ @id }\">\n"
        k << "#{ ' ' * indent }    <begin>#{ @begin }</begin>\n" unless @begin.nil?
        k << "#{ ' ' * indent }    <end>#{ @end }</end>\n" unless @end.nil?
        k << "#{ ' ' * indent }</#{ prefix }TimeSpan>\n"
        k
    end
end

class Feature < KMLObject
    # Abstract class
    attr_accessor :visibility, :open, :atom_author, :atom_link, :name,
        :addressdetails, :phonenumber, :snippet, :description, :abstractview,
        :timestamp, :timespan, :styleurl, :styleselector, :region, :metadata,
        :extendeddata, :styles

    def initialize (name = nil)
        super()
        @name = name
        @visibility = true
        @open = false
        @styles = []
    end

    def to_kml(indent = 0)
        k = super 
        k << kml_array([
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
                [@styleurl, 'styleUrl', true],
                [@styleselector, "<styleSelector>#{@styleselector.nil? ? '' : @styleselector.to_kml}</styleSelector>", false ],
                [@metadata, 'Metadata', false ],                  # XXX
                [@extendeddata, 'ExtendedData', false ]           # XXX
            ], (indent))
        k << styles_to_kml(indent)
        k << @timestamp.to_kml(indent) unless @timestamp.nil?
        k << @timespan.to_kml(indent) unless @timespan.nil?
        k << @region.to_kml(indent) unless @region.nil?
        k << yield if block_given?
        k
    end
    
    def styles_to_kml(indent)
        k = ''
        @styles.each do |a|
            k << a.to_kml(indent)
        end
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
    attr_accessor :styles
    def initialize(name = nil)
        super()
        @name = name
        @styles = []
        Document.instance.folders << self
    end

    def to_kml(indent = 0)
        h = "#{ ' ' * indent }<Folder id=\"#{@id}\">\n"
        h << super(indent + 4)
        @features.each do |a|
            h << a.to_kml(indent + 4)
        end
        h << "#{ ' ' * indent }</Folder>\n";
        h
    end
end

def get_stack_trace
    k = ''
    caller.each do |a| k << "#{a}\n" end
    k
end

class Document < Container
    include Singleton
    attr_accessor :flyto_mode, :folders, :tours

    def initialize
        @tours = []
        @folders = []
        @styles = []
    end

    def tour
        @tours << Tour.new if @tours.length == 0
        @tours.last
    end

    def folder
        if @folders.size == 0 then
            Folder.new
        end
        @folders.last
    end

    def styles_to_kml(indent)
        ''
    end

    def to_kml
        h = <<-doc_header
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
        doc_header

        h << super(4)

        # Print styles first
        @styles.map do |a| h << a.to_kml(4) unless a.attached? end

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

        super + <<-colorstyle
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
        super + <<-balloonstyle
#{ ' ' * indent }<BalloonStyle id="#{@id}">
#{ ' ' * indent }    <bgColor>#{@bgcolor}</bgColor>
#{ ' ' * indent }    <text>#{@text}</text>
#{ ' ' * indent }    <textColor>#{@textcolor}</textColor>
#{ ' ' * indent }    <displayMode>#{@displaymode}</displayMode>
#{ ' ' * indent }</BalloonStyle>
        balloonstyle
    end
end

class KMLxy
    attr_accessor :x, :y, :xunits, :yunits
    def initialize(x = 0.5, y = 0.5, xunits = :fraction, yunits = :fraction)
        @x = x
        @y = y
        @xunits = xunits
        @yunits = yunits
    end

    def to_kml(name, indent = 0)
        <<-kmlxy
#{ ' ' * indent}<#{ name } x="#{ @x }" y="#{ @y }" xunits="#{ @xunits }" yunits="#{ @yunits }" />
        kmlxy
    end
end

class Icon
    attr_accessor :href, :x, :y, :w, :h, :refreshMode, :refreshInterval, :viewRefreshMode, :viewRefreshTime, :viewBoundScale, :viewFormat, :httpQuery

    def initialize(href = nil)
        @href = href
    end

    def to_kml(indent = 0)
        k = "#{ ' ' * indent }<Icon>\n"
        k << kml_array([
            [@href, 'href', true],
            [@x, 'gx:x', true],
            [@y, 'gx:y', true],
            [@w, 'gx:w', true],
            [@h, 'gx:h', true],
            [@refreshMode, 'refreshMode', true],
            [@refreshInterval, 'refreshInterval', true],
            [@viewRefreshMode, 'viewRefreshMode', true],
            [@viewBoundScale, 'viewBoundScale', true],
            [@viewFormat, 'viewFormat', true],
            [@httpQuery, 'httpQuery', true],
        ], indent + 4)
        k << "#{ ' ' * indent }</Icon>\n"
    end
end

class IconStyle < ColorStyle
    attr_accessor :scale, :heading, :hotspot, :icon

    def initialize(href, scale = 1, heading = 0, hs_x = 0.5, hs_y = 0.5, hs_xunits = :fraction, hs_yunits = :fraction, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @scale = scale
        @heading = heading
        @icon = Icon.new(href) unless href.nil?
        @hotspot = KMLxy.new(hs_x, hs_y, hs_xunits, hs_yunits) unless (hs_x.nil? and hs_y.nil? and hs_xunits.nil? and hs_yunits.nil?)
    end

    def to_kml(indent = 0)
        k = <<-iconstyle1
#{ ' ' * indent }<IconStyle id="#{@id}">
#{ super(indent + 4) }
       iconstyle1
       k << "#{ ' ' * indent }    <scale>#{@scale}</scale>\n" unless @scale.nil?
       k << "#{ ' ' * indent }    <heading>#{@heading}</heading>\n" unless @heading.nil?
       k << @icon.to_kml(indent + 4) unless @icon.nil?
       k << "#{ ' ' * indent }    <hotSpot x=\"#{@hotspot.x}\" y=\"#{@hotspot.y}\" xunits=\"#{@hotspot.xunits}\" yunits=\"#{@hotspot.yunits}\" />\n" unless @hotspot.nil?
       k << "#{ ' ' * indent }</IconStyle>\n"
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
        k = "#{ ' ' * indent }<ListStyle id=\"#{@id}\">\n" + super
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

        k = <<-polystyle
#{ ' ' * indent }<PolyStyle id="#{@id}">
#{ super(indent + 4) }
#{ ' ' * indent }    <fill>#{@fill}</fill>
        polystyle
        k << "#{ ' ' * indent }    <outline>#{@outline}</outline>\n" unless @outline.nil?
        k << "#{ ' ' * indent }</PolyStyle>\n"
        k
    end
end

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
        k = ''
        k << super + "#{ ' ' * indent }<Style id=\"#{@id}\">\n"
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
        k = super + "#{ ' ' * indent }<StyleMap id=\"#{@id}\">\n"
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
        if @geometry.kind_of? KMLPoint then
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
        if view.respond_to? 'range' and not range.nil? then
            @view.range = range
        end
        super()
    end

    def to_kml(indent = 0)
        k = super + "#{ ' ' * indent }<gx:FlyTo>\n"
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

class TourControl < TourPrimitive
end

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
        k = super + "#{ ' ' * indent }<gx:Tour id=\"#{ @id }\">\n"
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

class Overlay < Feature
    attr_accessor :color, :drawOrder, :icon

    def initialize(icon, name = nil)
        super(name)
        if icon.respond_to?('to_kml') then
            @icon = icon
        elsif not icon.nil?
            @icon = Icon.new(icon.to_s)
        end
        Document.instance.folder << self
    end

    def to_kml(indent = 0)
        k = super(indent) + kml_array([
            [ @color, 'color', true ],
            [ @drawOrder, 'drawOrder', true ],
        ], indent + 4)
        k << @icon.to_kml(indent) unless @icon.nil?
        k
    end
end

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

    def to_kml(indent = 0, alt = false)
        name = alt ? 'LatLonAltBox' : 'LatLonBox'
        k = <<-latlonbox
#{ ' ' * indent }<#{ name }>
#{ ' ' * indent }    <north>#{ @north }</north>
#{ ' ' * indent }    <south>#{ @south }</south>
#{ ' ' * indent }    <east>#{ @east }</east>
#{ ' ' * indent }    <west>#{ @west }</west>
        latlonbox
        k << "#{ ' ' * indent }    <minAltitude>#{ @minAltitude }</minAltitude>\n" unless @minAltitude.nil?
        k << "#{ ' ' * indent }    <maxAltitude>#{ @maxAltitude }</maxAltitude>\n" unless @maxAltitude.nil?
        if (not @minAltitude.nil? or not @maxAltitude.nil?) then
            if @altitudeMode == :clampToGround or @altitudeMode == :absolute then
                altitudeModeString = "#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>\n"
            else
                altitudeModeString = "#{ ' ' * indent }    <gx:altitudeMode>#{ @altitudeMode }</gx:altitudeMode>\n"
            end
        end
        k << <<-latlonbox2
#{ ' ' * indent }    <rotation>#{ @rotation }</rotation>
#{ ' ' * indent }</#{ name }>
        latlonbox2
    end
end

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
        if @altitudeMode == :clampToGround or @altitudeMode == :absolute then
            k << "#{ ' ' * indent }    <altitudeMode>#{ @altitudeMode }</altitudeMode>\n"
        else
            k << "#{ ' ' * indent }    <gx:altitudeMode>#{ @altitudeMode }</gx:altitudeMode>\n"
        end
        k << @latlonbox.to_kml(indent + 4) unless @latlonbox.nil?
        k << @latlonquad.to_kml(indent + 4) unless @latlonquad.nil?
        k << "#{ ' ' * indent }</GroundOverlay>\n"
        k
    end
end

class Lod
    attr_accessor :minpixels, :maxpixels, :minfade, :maxfade
    def initialize(minpixels, maxpixels, minfade, maxfade)
        @minpixels = minpixels
        @maxpixels = maxpixels
        @minfade = minfade
        @maxfade = maxfade
    end

    def to_kml(indent = 0)

        <<-lod
#{ ' ' * indent }<Lod>
#{ ' ' * indent }    <minLodPixels>#{ @minpixels }</minLodPixels>
#{ ' ' * indent }    <maxLodPixels>#{ @maxpixels }</maxLodPixels>
#{ ' ' * indent }    <minFadeExtent>#{ @minfade }</minFadeExtent>
#{ ' ' * indent }    <maxFadeExtent>#{ @maxfade }</maxFadeExtent>
#{ ' ' * indent }</Lod>
        lod
    end
end

class Region < KMLObject
    attr_accessor :latlonaltbox, :lod

    def initialize(latlonaltbox, lod)
        super()
        @latlonaltbox = latlonaltbox
        @lod = lod
    end

    def to_kml(indent = 0)
        k = "#{' ' * indent}<Region id=\"#{@id}\">\n"
        k << @latlonaltbox.to_kml(indent + 4, true) unless @latlonaltbox.nil?
        k << @lod.to_kml(indent + 4) unless @lod.nil?
        k << "#{' ' * indent}</Region>\n"
        k
    end
end
