# vim:ts=4:sw=4:et:smartindent:nowrap
def fly_to(p, d = 0, r = 100, m = nil)
    m = Document.instance.flyto_mode if m.nil?
    FlyTo.new(p, r, d, m)
end

def set_flyto_mode_to(a)
    Document.instance.flyto_mode = a
end

def mod_popup_for(p, v)
    a = AnimatedUpdate.new
    if ! p.is_a? Placemark then
        raise "Can't show popups for things that aren't placemarks"
    end
    a << "<Change><Placemark targetId=\"#{p.id}\"><visibility>#{v}</visibility></Placemark></Change>"
    a
end

def hide_popup_for(p)
    mod_popup_for(p, 0)
end

def show_popup_for(p)
    mod_popup_for(p, 1)
end

def point(lo, la, alt=0, mode=nil, extrude = false)
    KMLPoint.new(lo, la, alt, mode.nil? ? :clampToGround : mode, extrude)
end

# Returns the KML that makes up the current Document, as a string.
def get_kml
    Document.instance.get_kml_document
end

def pause(p)
    Wait.new p
end

def name_tour(a)
    Document.instance.tour.name = a
end

def new_folder(name)
    Folder.new(name)
end

def name_folder(a)
    Document.instance.folder.name = a
end

def zoom_out(dist = 1000, dur = 0, mode = nil)
    l = Document.instance.tour.last_abs_view
    raise "No current position to zoom out from\n" if l.nil?
    l.range += dist
    FlyTo.new(l, nil, dur, mode)
end

# Creates a list of FlyTo elements to orbit and look at a given point (center),
# at a given range (in meters), starting and ending at given angles (in
# degrees) from the center, where 0 and 360 (and -360, and 720, and -980, etc.)
# are north. To orbit clockwise, make startHeading less than endHeading.
# Otherwise, it will orbit counter-clockwise. To orbit multiple times, add or
# subtract 360 from the endHeading. The tilt argument matches the KML LookAt
# tilt argument
def orbit(center, range = 100, tilt = 0, startHeading = 0, endHeading = 360)
    fly_to LookAt.new(center, startHeading, tilt, range), 2, nil

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
        fly_to LookAt.new(center, theta, tilt, range), 2, nil, 'smooth'
    end
    if lastval != endHeading then
        fly_to LookAt.new(center, endHeading, tilt, range), 2, nil, 'smooth'
    end
end

def sound_cue(href, ds = nil)
    SoundCue.new href, ds
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
