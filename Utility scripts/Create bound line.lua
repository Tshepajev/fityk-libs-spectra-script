-- Lua script for Fityk.

use_dataset = 15
line_position = 468.1
max_position_shift = 0.2
max_line_gwidth = 0.01
minimal_gwidth = 0.005

max_Voigt_shape = 10

-- Constructs string for parameters to be used with "guess Voigt"
function guess_parameter_constructor()
	
	F:execute("use @"..tostring(use_dataset))
	
	local line_index = #F:get_components(0)
	local function_type = "Voigt"
	local parameters = "guess %_" .. line_index .. " = " .. function_type .. " (height = "
	
	-- Get lower height correction
	local minimal_data_value = F:calculate_expr("min(y if a)")
	if minimal_data_value < 0 then minimal_data_value = 0 end -- physical constraint
	
	local height,max_height_value = 0,0
	
	-- average height of 3 pixels
	for i = -1, 1 do
		height = height + F:calculate_expr("y[index("..tostring(line_position)..") + "..tostring(i).."]") -- index gets the y-value index from wavelength
	end
	height = height / 3 - minimal_data_value -- get the averaged height - minimal_data_value at line location and set that as the guess value
	
	max_height_value = 1.33 * height -- 1.33x the pixel height as max bound
	
	-- Forces height to be positive and lower that 1.33 * pixel height. Guess is made at the wavelength's height
	local start_angle = math.asin((height - max_height_value / 2) / (max_height_value / 2)) -- angle at which height is at pixel height
	F:execute("$height_variable_"..tostring(line_index).." = ~"..tostring(start_angle))
	-- equation: height = max/2 + max/2 * sin(~angle), bounds from 0 to max data value*1.33
	parameters = parameters..tostring(max_height_value / 2).." + "..tostring(max_height_value / 2).." * sin($height_variable_"..tostring(line_index)..")"
	
	
	-- Center
	-- Angle variable
	F:execute("$center_variable_"..tostring(line_index).." = ~0")
	-- Center is inside given max shift e.g it's a compound variable
	-- equation: center = line_position + max_position_shift * sin(~angle)
	parameters = parameters..", center = "..tostring(line_position).." + "..tostring(max_position_shift).." * sin($center_variable_"..tostring(line_index)..")"
	
	
	
	if function_type == "Voigt" then -- Voigt
		--shape 
		-- Angle variable (shape starts at 1)
		F:execute("$shape_variable_"..tostring(line_index).." = ~-0.9273")
		-- equation: shape = max_Voigt_shape / 2 + max_Voigt_shape / 2 * sin(~angle) (binds it from 0 to 10) (1 is equal parts of Gaussian and Lorentzian and 0 should be pure Gaussian but isn't quite)
		parameters = parameters..", shape = "..tostring(max_Voigt_shape / 2).." + "..tostring(max_Voigt_shape / 2).." * sin($shape_variable_"..tostring(line_index)..")"
		
		-- gwidth angle variable, starts from 3pi/2 so that sin is minimal
		F:execute("$gwidth_variable_"..tostring(line_index).." = ~4.712")
		
		-- gwidth
		if max_line_gwidth == 0 then -- gwidth is locked variable
			parameters = parameters..", gwidth = "..tostring(minimal_gwidth)
		elseif max_line_gwidth >= minimal_gwidth then -- gwidth is bound with an angle variable
			-- equation: gwidth = (max + min) / 2 + (max - min) / 2 * sin(angle)
			parameters = parameters..", gwidth = "..tostring((max_line_gwidth + minimal_gwidth) / 2).." + "..tostring((max_line_gwidth - minimal_gwidth) / 2)..
								" * sin($gwidth_variable_"..tostring(line_index)..")"
		else -- gwidth is simple variable
			parameters = parameters..", gwidth = ~"..tostring(minimal_gwidth)
		end
	
	else -- Gaussian or Lorentzian
		local max_hwhm = max_line_gwidth / 1 -- the same column is used for gwidth and hwhm in input files
		local min_hwhm = minimal_gwidth / 1.2 -- because now it's hwhm instead of gwidth, if shape==0 then gwidth = 1.2 is the same as hwhm = 1
		
		-- hwhm angle variable, starts from 3pi/2 so that sin is minimal
		F:execute("$hwhm_variable_"..tostring(line_index).." = ~4.712")
		
		if max_line_gwidth == 0 then -- hwhm is locked variable
			parameters = parameters..", hwhm = "..tostring(min_hwhm)
		elseif max_hwhm >= min_hwhm then -- hwhm is bound with an angle variable
			-- equation: hwhm = (max + min) / 2 + (max - min) / 2 * sin(angle)
			parameters = parameters..", hwhm = "..tostring((max_hwhm + min_hwhm) / 2).." + "..tostring((max_hwhm - min_hwhm) / 2)..
								" * sin($hwhm_variable_"..tostring(line_index)..")"
		else -- hwhm is simple variable
			parameters = parameters..", hwhm = ~"..tostring(min_hwhm)
		end
	end
	
	parameters = parameters..")"
	return parameters
end


-- Create the line
F:execute(tostring(guess_parameter_constructor()))