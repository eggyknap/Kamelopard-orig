# vim:ts=4:sw=4:et:smartindent
require 'matrix'
#require 'Kameleopard_classes'

class NDPointList
    # Contains a list of N-dimensional numeric arrays

    attr_reader :dim

    def initialize(num)
        raise "Can't have an NDPointList with #{num} dimensions -- must be 1 or more" if num < 1
        @dim = num
        @points = []
    end

    def size
        return @points.size
    end

    def <<(a)
        # Append points to our list
        if a.kind_of? KMLPoint then
            if self.dim == 3 then
                @points << [a.longitude, a.latitude, a.altitude]
            else
                @points << [a.longitude, a.latitude]
            end
        elsif a.respond_to? 'dim' and @dim != a.dim then
            raise "Argument's dimension #{a.dim} must agree with our dimension #{@dim} to append to an NDPointList"
        else
            @points << a
        end
    end

    def last
        @points.last
    end

    def [](i)
        @points[i]
    end

    def x
        @points.collect do |a| a[0] end
    end

    def y
        if @dim >= 2 then
            @points.collect do |a| a[1] end
        else
            raise "NDPointList of size #{@dim} has no Y element"
        end
    end

    def z
        if @dim >= 2 then
            @points.collect do |a| a[2] end
        else
            raise "NDPointList of size #{@dim} has no Z element"
        end
    end

    def each(&blk)
        @points.each(&blk)
    end

    def interpolate(resolution = nil)
        # XXX Figure out how to implement the "resolution" argument
        STDERR.puts "resolution argument to NDPointList.interpolate is ignored" if resolution.nil?
        # Ruby implementation of Catmull-Rom splines (http://www.cubic.org/docs/hermite.htm)
        # Return NDPointList interpolating a path along all points in this list

        h = Matrix[
            [ 2,  -2,   1,   1 ],
            [-3,   3,  -2,  -1 ],
            [ 0,   0,   1,   0 ],
            [ 1,   0,   0,   0 ],
        ]

        result = NDPointList.new(@dim)

        # Calculate spline between every two points
        (0..(self.size-2)).each do |i|
            p1 = self[i]
            p2 = self[i+1]
            
            # Get surrounding points for calculating tangents
            if i <= 0 then pt1 = p1 else pt1 = self[i-1] end
            if i == self.size - 2 then pt2 = p2 else pt2 = self[i+2] end

            # Build tangent points into matrices to calculate tangents.
            t1 = 0.5 * ( Matrix[p2]  - Matrix[pt1] )
            t2 = 0.5 * ( Matrix[pt2] - Matrix[p1] )

            # Build matrix of Hermite parameters
            c = Matrix[p1, p2, t1.row(0), t2.row(0)]

            # Make a set of points
            (0..10).each do |t|
                r = t/10.0
                s = Matrix[[r**3, r**2, r, 1]]
                tmp = s * h
                p = tmp * c
                result << p.row(0).to_a
            end
        end
        result
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
