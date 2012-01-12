require 'rubygems'
require 'kamelopard'
require 'yaml'

# Reads config
#
# Params:
#
# * <tt>file</tt> - name of the yaml file
#
# Returns proper yaml object filled with data from the file.
# Raises exception if the file couldn't be parsed.
#
def get_config(file)
    begin
        return YAML.load(File.open(file))
    rescue ArgumentError => e
        raise "Could not parse #{file} #{e.message}"
    end
end


# Prefixes value from the yaml file with the kmz file name.
# If the file does not exist, the function returns only
# the value from config.
#
# Params:
#
# * <tt>config</tt> - YAML object
# * <tt>filename</tt> - name of the file
#
def build_full_path(params)
    config   = params[:config]
    filename = params[:filename]

    kmz = config["data_kmz"]

    return "#{kmz}/#{filename}" unless kmz.nil?
    return filename
end

def get_kml
    Kamelopard::Document.instance.get_kml_document
end

def wait(time)
    Kamelopard::Wait.new time
end


# prepare kml from the config
#############################################################################

# created overlay
# returns the overlay - is used later for animation
def create_overlay(params)
    icon            = params[:icon]
    description     = params[:description]

    overlay_icon    = Kamelopard::Icon.new icon

    overlay = Kamelopard::ScreenOverlay.new overlay_icon
    overlay.description = description

    return overlay
end

def animate_overlay(params)
    id              = params[:id]
    animation_time  = params[:animation_time]
    wait_time       = params[:wait_time]

    show_overlay(params)
    wait(wait_time)
    hide_overlay(params)
end

# Shows overlay
#
def show_overlay(params)
    set_overlay_visibility(:id => params[:id], :animation_time => params[:animation_time], :visible=>true)
end

# Hides overlay
#
def hide_overlay(params)
    set_overlay_visibility(:id => params[:id], :animation_time => params[:animation_time], :visible=>false)
end

def set_overlay_visibility(params)
    id              = params[:id]
    animation_time  = params[:animation_time]
    visibility      = params[:visible] ? 'ffffffff' : '00ffffff'

    au = Kamelopard::AnimatedUpdate.new
    au.duration = animation_time
    a = XML::Node.new 'Change'
    b = XML::Node.new 'ScreenOverlay'
    b.attributes['targetId'] = id
    c = XML::Node.new 'color'
    d = XML::Node.new_text visibility
    c << d
    b << c
    a << b
    au << a
end

def make_balloon_style(params)
    text = params[:text]

    Kamelopard::BalloonStyle.new text
end

def make_icon_style(params)
    href = params[:href]
    scale = 1

    icon_style = Kamelopard::IconStyle.new href
    icon_style.scale= scale

    return icon_style
end

def make_style(params)
    style = Kamelopard::Style.new
    params.each{|k,v| style.send("#{k}=".to_sym, params[k])}

    return style
end



def fly_to(params)
    duration = params[:duration]
    fly_mode = params[:fly_to_mode]
    lon      = params[:lon]
    lat      = params[:lat]
    altitude = params[:altitude]
    heading  = params[:heading]
    tilt     = params[:tilt]
    range    = params[:range]
    alt_mode = params[:altitude_mode]


    point = Kamelopard::Point.new lon, lat, altitude, alt_mode
    view = Kamelopard::LookAt.new point, heading, tilt, range, alt_mode
    flyto = Kamelopard::FlyTo.new view, range, duration, fly_mode

    return flyto
end

def hide_balloon(params)
    placemark = params[:placemark]
    animate_balloon :placemark => placemark, :hide => true
end

def show_balloon(params)
    placemark = params[:placemark]
    animate_balloon :placemark => placemark, :show => true
end

def animate_balloon(params)
    placemark = params[:placemark]
    if params[:show] && params[:hide]
        raise "Cannot have :show and :hide at the same time"
    end
    flag = 1 if params[:show]
    flag = 0 if params[:hide]

    up = Kamelopard::AnimatedUpdate.new
    a = XML::Node.new 'Change'
    b = XML::Node.new 'Placemark'
    b.attributes['targetId'] = placemark.obj_id
    c = XML::Node.new 'gx:balloonVisibility'
    c << XML::Node.new_text(flag.to_s)
    b << c
    a << b
    up << a
end

def add_placemark_to_folder(params)
    placemark = params[:placemark]

    doc = Kamelopard::Document.instance
    doc.folders[0] << placemark
end

# Zooms out between two points.
#
#
# Params:
# * <tt>:old</tt> Old point
# * <tt>:new</tt> New point
# * <tt>:altitude</tt> Altitude
# * <tt>:duration</tt> Duration of zooming out
# * <tt>:wait</tt> Wait time at the highest point
# * <tt>:range</tt> Range from the point
def zoom_out(params)

    old_point   = params[:old]
    new_point   = params[:new]
    duration    = params[:duration]
    altitude    = params[:altitude]
    wait_time   = params[:wait]
    range       = params[:range]
    fly_to_mode = params[:fly_to_mode]
    alt_mode    = params[:altitude_mode]

    new_lon = (old_point.longitude.to_f + new_point.longitude.to_f) / 2.0
    new_lat = (old_point.latitude.to_f + new_point.latitude.to_f) / 2.0

    fly_to  :lon=>new_lon, :lat=>new_lat,
            :duration=>duration,
            :range=>range, :tilt=>0, :heading=>0,
            :altitude=>0,
            :fly_to_mode=>fly_to_mode,
            :altitude_mode=>alt_mode

    wait wait_time

end

