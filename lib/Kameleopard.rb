require 'singleton'

# Print out a set of kml fields. Expects an array argument. Each entry in the
# array is itself an array, containing two strings and a boolean. If the first
# string is nil, the function won't print anything for that element. If it's
# not null, it consults the boolean. True values tell the function to treat the
# second string as a KML element name, and print it along with XML decorators
# and the field value. False values mean just print the second string, with no
# decorators and no other values
def kml_array(m)
    k = ''
    m.map do |a|
        r = ''
        if ! a[0].nil? then
            if a[2] then
                r << '      <' << a[1] << '>' << a[0].to_s << '</' << a[1] << ">\n"
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

class KMLStatus
    include Singleton
    attr_accessor :flyto_mode, :folders, :tours, :styles

    def initialize
        @tours = []
        @folders = []
        @styles = []
    end

    def cur_tour
        @tours << Tour.new if @tours.length == 0
        @tours.last
    end

    def get_document_kml
        h = <<-doc_header
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
        doc_header

        # Print styles first
        @styles.map do |a| h << a.to_kml end

        # then folders
        @folders.map do |a| h << a.to_kml end

        # then tours
        @tours.map do |a| h << a.to_kml end
        h << '</Document>'

        h
    end
end

class Sequence
    include Singleton
    def initialize
        @value = 1
    end

    def next
        return @value
        @value += 1
    end
end

class KMLObject
    attr_reader :id

    def initialize
        @id = "#{self.class.name}_#{ Sequence.instance.next }"
    end

    def to_kml
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

    def to_kml
        <<-point_kml
            <Point id="#{ @id }">
                <extrude>#{ @extrude ? 1 : 0 }</extrude>
                <altitudeMode>#{ @altitudeMode }</altitudeMode>
                <coordinates>#{ @longitude }, #{ @latitude }, #{ @altitude }</coordinates>
            </Point>
        point_kml
    end
end

class AbstractView < KMLObject
end

class Camera < AbstractView
end

class LookAt < AbstractView
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

    def to_kml
        k = "    <LookAt id=\"#{@id}\">\n"
        # XXX Need to include AbstractView stuff here sometime
        k << kml_array([
            [ @point.longitude, 'longitude', true ],
            [ @point.latitude, 'latitude', true ],
            [ @point.altitude, 'altitude', true ],
            [ @point.altitude, 'altitude', true ],
            [ @point.altitudeMode, 'altitudeMode', true ],
            [ @heading, 'heading', true ],
            [ @tilt, 'tilt', true ],
            [ @range, 'range', true ]
        ])
        k << "    </LookAt>\n"
    end
end

class Feature < KMLObject
    # Abstract class
    attr_accessor :visibility, :open, :atom_author, :atom_link,
        :addressdetails, :phonenumber, :snippet, :description, :abstractview,
        :timeprimitive, :styleurl, :styleselector, :region, :metadata,
        :extendeddata

    def initialize (name = nil)
        super()
        @name = name
        @visibility = true
        @open = false
    end

    def to_kml
        k = ''
        kml_array [
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
        ]
        k << yield if block_given?
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

    def to_kml
        <<-colorstyle
            <color>#{@color}</color>
            <colorMode>#{@colormode}</colormode>
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

    def to_kml
        <<-balloonstyle
                <BalloonStyle id="#{@id}">
                    <bgColor>#{@bgcolor}</bgcolor>
                    <text>#{@text}</text>
                    <textcolor>#{@textcolor}</textcolor>
                    <displaymode>#{@displaymode}</displaymode>
                </BalloonStyle>
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

    def to_kml
        <<-iconstyle
                <IconStyle id="#{@id}">
                    #{ super }
                    <scale>#{@scale}</scale>
                    <heading>#{@heading}</heading>
                    <Icon>
                        <href>#{@href}</href>
                    </Icon>
                    <hotSpot x="#{@hs_x}" y="#{@hs_y}" xunits="#{@hs_xunits}" yunits="#{@hs_yunits}" />
                </IconStyle>
        iconstyle
    end
end

class LabelStyle < ColorStyle
    attr_accessor :scale

    def initialize(scale = 1, color = 'ffffffff', colormode = :normal)
        super(color, colormode)
        @scale = scale
    end

    def to_kml
        <<-labelstyle
                <LabelStyle id="#{@id}">
                    #{ super }
                    <scale>#{@scale}</scale>
                </LabelStyle>
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

    def to_kml
        <<-linestyle
                <LineStyle id="#{@id}">
                    #{ super }
                    <width>#{@width}</width>
                    <gx:outerColor>#{@outercolor}</gx:outerColor>
                    <gx:outerWidth>#{@outerwidth}</gx:outerWidth>
                    <gx:physicalWidth>#{@physicalwidth}</gx:physicalWidth>
                </LineStyle>
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

    def to_kml
        k = "                <ListStyle id=\"#{@id}\">\n"
        k << kml_array([
            [@listitemtype, 'listItemType', true],
            [@bgcolor, 'bgColor', true]
        ])
        if (! @state.nil? or ! @href.nil?) then
            k << "                  <ItemIcon>\n"
            k << "                      <state>#{@state}</state>\n" unless @state.nil? 
            k << "                      <href>#{@href}</href>\n" unless @href.nil? 
            k << "                  </ItemIcon>\n"
        end
        k << "                </ListStyle>\n"
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

    def to_kml
        <<-polystyle
                <PolyStyle id="#{@id}">
                    #{ super }
                    <fill>#{@fill}</fill>
                    <outline>#{@outline}</outline>
                </PolyStyle>
        polystyle
    end
end

class StyleSelector < KMLObject
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

    def to_kml
        k = "               <Style id=\"#{@id}\">\n"
        k << @icon.to_kml unless @icon.nil?
        k << @label.to_kml unless @label.nil?
        k << @line.to_kml unless @line.nil?
        k << @poly.to_kml unless @poly.nil?
        k << @balloon.to_kml unless @balloon.nil?
        k << @list.to_kml unless @list.nil?
        k << "               </Style>\n"
        k
    end
end

class StyleMap < StyleSelector
    def initialize(pairs = {})
        @pairs = pairs
    end

    def <<
        
    end

    def to_kml
        k <<-stylemap_kml
            <StyleMap id="#{@id}">

            </StyleMap>
        stylemap_kml
    end
=begin
  <Pair id="ID">
    <key>normal</key>              <!-- kml:styleStateEnum:  normal or highlight -->
    <styleUrl>...</styleUrl> or <Style>...</Style>
  </Pair>
=end
end

class Placemark < Feature
    attr_accessor :name, :geometry
    def initialize(name = nil, geo = nil)
        super(name)
        @geometry = geo
    end
    
    def to_kml
        a = "   <Placemark id=\"#{ @id }\">\n"
        a << super {
            @geometry.nil? ? '' : @geometry.to_kml
        }
        a << "\n    </Placemark>"
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
end

class FlyTo < TourPrimitive
    attr_accessor :duration, :mode, :view

    def initialize(view = nil, duration = 0, mode = :bounce)
        @duration = duration
        @mode = mode
        @view = view
    end

    def to_kml
        k = "       <gx:FlyTo>\n"
        k << kml_array([
            [ @duration, 'gx:duration', true ],
            [ @mode, 'gx:flyToMode', true ]
        ])
        k << @view.to_kml unless @view.nil?
        k << "       </gx:FlyTo>\n"
    end
end

class AnimatedUpdate < TourPrimitive
    # For now, the user has to specify the change / create / delete elements in
    # the <Update> manually, rather than creating objects.
    attr_accessor :target, :delayedstart, :updates, :duration

    def initialize(updates = [], duration = 0, target = '', delayedstart = nil)
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

    def to_kml
        k = <<-animatedupdate_kml
            <gx:AnimatedUpdate>
                <gx:duration>#{@duration}</gx:duration>
        animatedupdate_kml
        k << "              <gx:delayeStart>#{@delayedstart}</gx:delayedStart>\n" unless @delayedstart.nil?
        k << "              <targetHref>#{@target}</targetHref>\n"
        k << "              <Update>\n"
        k << "                  " << @updates.join("\n                  ")
        k << "              </Update>\n         </gx:AnimatedUpdate>\n"
        k
    end
end

class TourControl < TourPrimitive
end

class Wait < TourPrimitive
    attr_accessor :duration
    def initialize(duration = 0)
        @duration = duration
    end

    def to_kml
        <<-wait_kml
            <gx:Wait><gx:duration>#{@duration}</gx:duration></gx:Wait>
        wait_kml
    end
end

class SoundCue < TourPrimitive
end

class Tour < KMLObject
    def initialize(name = nil)
        @name = name
        @items = []
    end

    # Add another element to a tour
    def <<(a)
        @items << a
    end

    def to_kml
        k = <<-tour_kml
           <gx:Tour id="#{ @id }">
              <gx:Playlist>
        tour_kml

        @items.map do |a| k << a.to_kml << "\n" end

        k << "  </gx:Playlist></gx:Tour>\n"
        k
    end
end

def fly_to(p, d = 0, m = nil)
    m = KMLStatus.instance.flyto_mode if m.nil?
    KMLStatus.instance.cur_tour << FlyTo.new(p, d, m)
end

def set_flyto_mode_to(a)
    KMLStatus.instance.flyto_mode = a
end

def mod_popup_for(p, v)
    a = AnimatedUpdate.new
    if ! p.is_a? Placemark then
        raise "Can't show popups for things that aren't placemarks"
    end
    a << "<Change><Placemark targetId=\"#{p.id}\"><visibility>#{v}</visibility></Placemark></Change>"
    KMLStatus.instance.cur_tour << a
end

def hide_popup_for(p)
    mod_popup_for(p, 0)
end

def show_popup_for(p)
    mod_popup_for(p, 1)
end

def point(lo, la, alt=0, mode=nil, extrude = false)
    Point.new(lo, la, alt, mode.nil? ? :clampToGround : mode, extrude)
end

def get_kml
    KMLStatus.instance.get_document_kml
end
