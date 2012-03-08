# vim:ts=4:sw=4:et:smartindent:nowrap
def fly_to(p, d = 0, r = 100, m = nil)
    m = Kamelopard::Document.instance.flyto_mode if m.nil?
    Kamelopard::FlyTo.new(p, r, d, m)
end

def set_flyto_mode_to(a)
    Kamelopard::Document.instance.flyto_mode = a
end

def mod_popup_for(p, v)
    au = Kamelopard::AnimatedUpdate.new
    if ! p.is_a? Kamelopard::Placemark then
        raise "Can't show popups for things that aren't placemarks"
    end
    a = XML::Node.new 'Change'
    b = XML::Node.new 'Placemark'
    b.attributes['targetId'] = p.obj_id
    c = XML::Node.new 'visibility'
    c << XML::Node.new_text(v.to_s)
    b << c
    a << b
    au << a
end

def hide_popup_for(p)
    mod_popup_for(p, 0)
end

def show_popup_for(p)
    mod_popup_for(p, 1)
end

def point(lo, la, alt=0, mode=nil, extrude = false)
    Kamelopard::Point.new(lo, la, alt, mode.nil? ? :clampToGround : mode, extrude)
end

# Returns the KML that makes up the current Kamelopard::Document, as a string.
def get_kml
    Kamelopard::Document.instance.get_kml_document
end

def get_kml_string
    get_kml.to_s
end

def pause(p)
    Kamelopard::Wait.new p
end

def name_tour(a)
    Kamelopard::Document.instance.tour.name = a
end

def new_folder(name)
    Kamelopard::Folder.new(name)
end

def name_folder(a)
    Kamelopard::Document.instance.folder.name = a
end

def zoom_out(dist = 1000, dur = 0, mode = nil)
    l = Kamelopard::Document.instance.tour.last_abs_view
    raise "No current position to zoom out from\n" if l.nil?
    l.range += dist
    Kamelopard::FlyTo.new(l, nil, dur, mode)
end

# Creates a list of FlyTo elements to orbit and look at a given point (center),
# at a given range (in meters), starting and ending at given angles (in
# degrees) from the center, where 0 and 360 (and -360, and 720, and -980, etc.)
# are north. To orbit clockwise, make startHeading less than endHeading.
# Otherwise, it will orbit counter-clockwise. To orbit multiple times, add or
# subtract 360 from the endHeading. The tilt argument matches the KML LookAt
# tilt argument
def orbit(center, range = 100, tilt = 0, startHeading = 0, endHeading = 360)
    fly_to Kamelopard::LookAt.new(center, startHeading, tilt, range), 2, nil

    # We want at least 5 points (arbitrarily chosen value), plus at least 5 for
    # each full revolution

    # When I tried this all in one step, ruby told me 360 / 10 = 1805. I'm sure
    # there's some reason why this is a feature and not a bug, but I'd rather
    # not look it up right now.
    num = (endHeading - startHeading).abs
    den = ((endHeading - startHeading) / 360.0).to_i.abs * 5 + 5
    step = num / den
    step = 1 if step < 1
    step = step * -1 if startHeading > endHeading

    lastval = startHeading
    startHeading.step(endHeading, step) do |theta|
        lastval = theta
        fly_to Kamelopard::LookAt.new(center, theta, tilt, range), 2, nil, 'smooth'
    end
    if lastval != endHeading then
        fly_to Kamelopard::LookAt.new(center, endHeading, tilt, range), 2, nil, 'smooth'
    end
end

def sound_cue(href, ds = nil)
    Kamelopard::SoundCue.new href, ds
end

# XXX This implementation of orbit is trying to do things the hard way, but the code might be useful for other situations where the hard way is the only possible one
# def orbit(center, range = 100, startHeading = 0, endHeading = 360)
#     p = ThreeDPointList.new()
# 
#     # Figure out how far we're going, and d
#     dist = endHeading - startHeading
# 
#     # We want at least 5 points (arbitrarily chosen value), plus at least 5 for each full revolution
#     step = (endHeading - startHeading) / ((endHeading - startHeading) / 360.0).to_i * 5 + 5
#     startHeading.step(endHeading, step) do |theta|
#         p << KMLPoint.new(
#             center.longitude + Math.cos(theta), 
#             center.latitude + Math.sin(theta), 
#             center.altitude, center.altitudeMode)
#     end
#     p << KMLPoint.new(
#         center.longitude + Math.cos(endHeading), 
#         center.latitude + Math.sin(endHeading), 
#         center.altitude, center.altitudeMode)
# 
#     p.interpolate.each do |a|
#         fly_to 
#     end
# end

module TelemetryProcessor
    Pi = 3.1415926535

    def TelemetryProcessor.get_heading(p)
        x1, y1, x2, y2 = [ p[1][0], p[1][1], p[2][0], p[2][1] ]

        h = Math.atan((x2-x1) / (y2-y1)) * 180 / Pi
        h = h + 180.0 if y2 < y1
        h
    end

    def TelemetryProcessor.get_dist2(x1, y1, x2, y2)
        Math.sqrt( (x2 - x1)**2 + (y2 - y1)**2).abs
    end

    def TelemetryProcessor.get_dist3(x1, y1, z1, x2, y2, z2)
        Math.sqrt( (x2 - x1)**2 + (y2 - y1)**2 + (z2 - z1)**2 ).abs
    end

    def TelemetryProcessor.get_tilt(p)
        x1, y1, z1, x2, y2, z2 = [ p[1][0], p[1][1], p[1][2], p[2][0], p[2][1], p[2][2] ]
        smoothing_factor = 10.0
        dist = get_dist3(x1, y1, z1, x2, y2, z2)
        dist = dist + 1
                # + 1 to avoid setting dist to 0, and having div-by-0 errors later
        t = Math.atan((z2 - z1) / dist) * 180 / Pi / @@options[:exaggerate]
                # the / 2.0 is just because it looked nicer that way
        90.0 + t
    end

        # roll = get_roll(last_last_lon, last_last_lat, last_lon, last_lat, lon, lat)
    def TelemetryProcessor.get_roll(p)
        x1, y1, x2, y2, x3, y3 = [ p[0][0], p[0][1], p[1][0], p[1][1], p[2][0], p[2][1] ]
        return 0 if x1.nil? or x2.nil?

        # Measure roll based on angle between P1 -> P2 and P2 -> P3. To be really
        # exact I ought to take into account altitude as well, but ... I don't want
        # to

        # Set x2, y2 as the origin
        xn1 = x1 - x2
        xn3 = x3 - x2
        yn1 = y1 - y2
        yn3 = y3 - y2
        
        # Use dot product to get the angle between the two segments
        angle = Math.acos( ((xn1 * xn3) + (yn1 * yn3)) / (get_dist2(0, 0, xn1, yn1).abs * get_dist2(0, 0, xn3, yn3).abs) ) * 180 / Pi

#    angle = angle > 90 ? 90 : angle
        @@options[:exaggerate] * (angle - 180)
    end

    def TelemetryProcessor.fix_coord(a)
        a = a - 360 if a > 180
        a = a + 360 if a < -180
        a
    end

    def TelemetryProcessor.add_flyto(p)
        # p is an array of three points, where p[0] is the earliest. Each point is itself an array of [longitude, latitude, altitude].
        heading = get_heading p
        tilt = get_tilt p
        # roll = get_roll(last_last_lon, last_last_lat, last_lon, last_lat, lon, lat)
        roll = get_roll p
        #p = Kamelopard::Point.new last_lon, last_lat, last_alt, { :altitudeMode => :absolute }
        point = Kamelopard::Point.new p[1][0], p[1][1], p[1][2], { :altitudeMode => :absolute }
        c = Kamelopard::Camera.new point, { :heading => heading, :tilt => tilt, :roll => roll, :altitudeMode => :absolute }
        f = Kamelopard::FlyTo.new c, { :duration => @@options[:pause], :mode => :smooth }
        f.comment = "#{p[1][0]} #{p[1][1]} #{p[1][2]} to #{p[2][0]} #{p[2][1]} #{p[2][2]}"
    end

    def TelemetryProcessor.options=(a)
        @@options = a
    end
end

def tour_from_points(points, options = {})
    options.merge!({
        :pause => 1,
        :exaggerate => 1
    }) { |key, old, new| old }
    TelemetryProcessor.options = options
    (0..(points.size-3)).each do |i|
        TelemetryProcessor::add_flyto points[i, 3]
    end
end

