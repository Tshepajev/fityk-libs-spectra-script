-- Lua script for Fityk.
-- Loads nr_of_lines number of Gaussian functions and a constant so that you
-- can colour them for analyze_and_plot.lua script output

nr_of_lines=40

-- Cleans the program from datasets, functions and variables
F:execute("reset")

-- Generates a constant
F:execute("%_0=Constant(a=500)")
F:execute("F+=%_0")

-- Generates nr_of_lines Gaussians
for i=1,nr_of_lines,1 do
  F:execute("%_"..i.."=Gaussian(height=500, hwhm=0.4, center="..(i*4)..")")
  F:execute("F+=%_"..i)
end
  