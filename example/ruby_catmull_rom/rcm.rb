# vim:ts=4:sw:et:smartindent
# Ruby implementation of Catmull-Rom splines (http://www.cubic.org/docs/hermite.htm)
# These will be useful for calculating paths, etc., in N dimensions
#
# In short, s is the interpolation point we're interested in
#           P1 is the first endpoint, P2 the second
#           T1 and T2 are tangent vectors to the first and second endpoints (see below)
#           h is a matrix of Hermitian coefficients
#
#                                         |  2  -2   1   1 |            | P1 |
#      S =  | s^3  s^2  s  1 |       h =  | -3   3  -2  -1 |       C =  | P2 |
#                                         |  0   0   1   0 |            | T1 |
#                                         |  1   0   0   0 |            | T2 |
#
#  The Hermitian curve at any point s is S * h * C
#
#  Tangents can be anything; for the Catmull-Rom spline specifically, they're calculated like this:
#  T[i] = 0.5 * ( P[i+1] - P[i-1])
#
#  I'm not sure what to do when P[i+1] or P[i-1] are undefined, so I'm just
#  using P[0] and P[n] for those (where n is the number of total points)

require 'yaml'
require 'matrix'

def read_points()
    points = []
    STDIN.each do |a|
        points << (a.split(/\s+/).map { |a| a.to_f })  unless a =~ /^#/
    end
    return points
end

def do_spline(points)
    h = Matrix[
        [ 2,  -2,   1,   1 ],
        [-3,   3,  -2,  -1 ],
        [ 0,   0,   1,   0 ],
        [ 1,   0,   0,   0 ],
    ]

    # Between every two points, calculate a spline
    (0 .. (points.length - 2)).each do |i|
        STDERR.puts "Doing points #{i} and #{i+1}"
        p1 = points[i]
        p2 = points[i + 1]

        # Get surrounding points for calculating tangents
        if i <= 0 then pt1 = p1 else pt1 = points[i-1] end
        if i == points.length - 2 then pt2 = p2 else pt2 = points[i+2] end

        # Build tangent points into matrices to calculate tangents.
        t1 = 0.5 * ( Matrix[p2]  - Matrix[pt1] )
        t2 = 0.5 * ( Matrix[pt2] - Matrix[p1] )

        # Build matrix of Hermite parameters
        c = Matrix[p1, p2, t1.row(0), t2.row(0)]

        # Values for s should go from 0 to 1, apparently. This makes intuitive
        # sense, now that I figured it out experimentally
        (0..10).each do |t|
            r = t/10.0
            s = Matrix[[r**3, r**2, r, 1]]
            tmp = s * h
            point = tmp * c
            puts "#{point[0, 0]}  #{point[0, 1]}  #{point[0, 2]}"
        end

    end
end

points = read_points
do_spline points
