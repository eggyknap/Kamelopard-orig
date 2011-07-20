# Accepts point data, expected in the form of seven files named xy, akima,
# akima_periodic, cspline, cspline_periodic, linear, and polynomia (see
# gsltest.rb) and plots it all to show how the different spline types behave

akima <- data.frame(read.table('akima'))
akima_periodic <- data.frame(read.table('akima_periodic'))
cspline <- data.frame(read.table('cspline'))
cspline_periodic <- data.frame(read.table('cspline_periodic'))
linear <- data.frame(read.table('linear'))
polynomial <- data.frame(read.table('polynomial'))
xy <- data.frame(read.table('xy'))

png('spline_type_example.png')
plot(xy)
lines(akima, lwd=2, col='blue')
lines(akima_periodic, lwd=2, col='blue', lty=2)
lines(cspline, lwd=2, col='red')
lines(cspline_periodic, lwd=2, col='red', lty=2)
lines(linear, lwd=2, col='green')
lines(polynomial, lwd=2, col='orange')

legend('bottomright', c('akima', 'akima-periodic', 'cspline', 'cspline-periodic', 'linear', 'polynomial'), col=c('blue', 'blue', 'red', 'red', 'green', 'orange'), lwd=2, lty=c(1, 2, 1, 2, 1, 1))

dev.off()
