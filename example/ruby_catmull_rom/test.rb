require 'matrix'
require 'yaml'

a = Matrix[[1,2,3,4], [2,3,4,5]]
b = Matrix[[1,2], [2,3], [3,4], [4,5]]

puts a.to_yaml
puts b.to_yaml
puts (a*b).to_yaml
