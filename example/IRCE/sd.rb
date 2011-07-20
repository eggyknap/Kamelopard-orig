$LOAD_PATH << './lib'
require 'Kameleopard'
require 'csv'

a = STDIN.read
cur_emp = nil

name_folder "End Point Employee Tour Data"
name_tour "End Point Employee Tour"

CSV.parse(a) do |row|
    if row[0] == 'POI' then
        dummy, name, lat, long, desc = row
        poi_p = point long, lat
        poi = Placemark.new name, poi_p
        poi.description = desc
        show_popup_for poi
        fly_to poi, 3
        pause 3
        hide_popup_for poi
    else
        if not cur_emp.nil? then
            fly_to cur_emp, 2
            zoom_out
            hide_popup_for cur_emp unless 
            pause 1
        end
        name, id, lat, long, city, state, zip, url, year, title = row
        p = point long, lat
        cur_emp = Placemark.new name, p
        cur_emp.description = "#{year} #{title}"
        fly_to cur_emp, 5
        show_popup_for cur_emp
        pause 3
    end
end

puts get_kml
