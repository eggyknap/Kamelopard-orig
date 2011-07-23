# vim:ts=4:sw:et:smartindent
# Ruby implementation of Catmull-Rom splines (http://www.cubic.org/docs/hermite.htm)
# These will be useful for calculating paths, etc., in N dimensions
#
# In short, s is the interpolation point we're interested in
#           P1 is the first endpoint, P2 the second
#           T1 and T2 are tangent vectors to the first and second endpoints (see below)
#           h is a matrix of Hermitian coefficients
#
#           | s^3 |            | P1 |             |  2  -2   1   1 |
#      S =  | s^2 |       C =  | P2 |        h =  | -3   3  -2  -1 |
#           | s^1 |            | T1 |             |  0   0   1   0 |
#           | 1   |            | T2 |             |  1   0   0   0 |
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

        # I'm not sure how many steps to do, since presumably values of s could
        # reach infinity, and presumably at some point I'll pass my endpoint
        # and want to start on a new curve. For now I'll do 1..10 in .1 increments
        (15..100).each do |t|
            r = t/10.0
            s = Matrix[[r**3], [r**2], [r], [1]]
            puts s.to_yaml
            puts "------"
            puts h.to_yaml
            puts "------"
            puts c.to_yaml
            tmp = s * h
            point = tmp * c
            puts point.to_yaml
        end

    end
end

points = read_points
do_spline points
