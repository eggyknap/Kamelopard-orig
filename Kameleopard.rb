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
    a = a.upcase.strip

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

    def to_kml
        raise "to_kml for this object (#{ self }) isn't yet defined!"
    end
end

class Geometry < KMLObject
end

class Point < Geometry
    attr_accessor :id, :longitude, :latitude, :altitude, :altitudeMode, :extrude
    def initialize(long, lat, alt=0, altmode=:clampToGround, extrude=false)
        @longitude = convert_coord(long)
        @latitude = convert_coord(lat)
        @altitude = alt
        @altitudeMode = altmode
        @extrude = extrude

        @id = "point_#{Sequence.instance.next}"
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

class AbstractView
=begin
<!-- abstract element; do not create -->
<!-- AbstractView -->                   <!-- Camera, LookAt -->                
  <!-- extends Object -->
  <TimePrimitive>...</TimePrimitive>     <!-- gx:TimeSpan or gx:TimeStamp -->
  <gx:ViewerOptions>
      <gx:option name=" " enabled=boolean />   <!-- name="streetview", "historicalimagery", 
                                                        or "sunlight" -->
  </gx:ViewerOptions>
<-- /AbstractView -->
=end
end

class Camera < AbstractView
end

class LookAt < AbstractView
    def initialize(point = nil, heading = 0, tilt = 0, range = 0)
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
        @id = "lookAt_#{ Sequence.instance.next }"
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
            [@styleselector, 'StyleSelector', false ],        # XXX
            [@region, 'Region', false ],                      # XXX
            [@metadata, 'Metadata', false ],                  # XXX
            [@extendeddata, 'ExtendedData', false ]           # XXX
        ]
        k << yield if block_given?
    end
end

class Placemark < Feature
    attr_accessor :name, :geometry
    def initialize(name = nil, geo = nil)
        super(name)
        @geometry = geo
        @id = "placemark_#{Sequence.instance.next}"
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

class TourPrimitive
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
        @updates << a
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

class Tour
    def initialize(name = nil)
        @id = "tour_#{ Sequence.instance.next }"
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
