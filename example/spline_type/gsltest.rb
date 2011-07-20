require "gsl"

# Prints a set of points, followed by points from the spline interpolation using each of GSL's six available methods
# Separate these into files, one per type, and see graph.r for R code to plot it all

STDERR.puts "Running interpolation tests (interp)..."

x = GSL::Vector.alloc(0..9)
y = GSL::Vector.alloc(0..9)
puts "#m=0,S=2"
0.upto(9) do |i|
        x[i] = i + 0.5 * Math.sin(i)
        y[i] = i + Math.cos(i * i)
printf "%g %g\n", x[i], y[i]
end

#acc = GSL::Interp.alloc(
type = [GSL::Interp::LINEAR, GSL::Interp::CSPLINE, GSL::Interp::AKIMA, GSL::Interp::POLYNOMIAL, GSL::Interp::CSPLINE_PERIODIC, GSL::Interp::AKIMA_PERIODIC]
type.each_index do |k|
        i = GSL::Interp.alloc(type[k], 10)
        # Interpolation::Interp.new(type[k], 10)
#        puts "#{i.name}\n"
        ret = i.init(x, y)
        #STDERR.puts ret

        puts "#m=#{k},S=0"
        xi = x[0]
        #d = Result.new
        while (xi < x[9]) do
                yi = i.eval(x, y, xi)
                printf "%g %g\n", xi, yi
                xi += 0.01
        end

#        acc.reset
end

STDERR.puts "\ndone."

