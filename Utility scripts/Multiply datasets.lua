-- Lua script for Fityk.
-- Multiplies two datasets by pixel value
function main()
  local modifiable_dataset = 0
  local multiplier_dataset = 1
  
  -- Save multiplier values
  F:execute("use @"..tostring(multiplier_dataset))
  local data_n = F:calculate_expr("M")
  multipliers = {}
  for i = 0, data_n - 1 do
    multipliers[i] = F:calculate_expr("Y["..(i).."]")
  end

  -- Multiply the values
  F:execute("use @"..tostring(modifiable_dataset))
  for i = 0, data_n - 1 do
    pcall(function() -- catch errors in case of nan values
      F:execute("Y["..(i).."] = y["..(i).."] * "..tostring(multipliers[i]))
    end)
  end
  
  print("Multiplication of " .. modifiable_dataset .. " with ".. multiplier_dataset .. " done")
end
main()