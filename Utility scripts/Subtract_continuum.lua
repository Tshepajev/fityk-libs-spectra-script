-- Lua script for Fityk.
-- Subtract background from all datasets
datasetnr = F:get_dataset_count()
for i=0,datasetnr - 1 do
  F:execute("use @"..i)
  
  -- Add polynomial
  --F:execute("@"..i..": guess Cubic")
  --F:execute("@"..i..":fit")
  
  -- Subtract background
  --local components = F:get_components(i)
  --local background = F:calculate_expr("%"..tostring(components[#components-1].name)..".a0")
  --F:execute("Y = y - " .. tostring(background))
  
  -- Delete polynomial
  --F:execute("delete %"..components[#components-1].name)
  
  -- Subtract roughly background
  local background = F:calculate_expr("min(Y)")
  F:execute("Y = y - " .. tostring(background))
  
  
  -- Normalize by area
  local area = F:calculate_expr("sum(Y)")
  if area < 0 then area = - area end
  F:execute("Y = Y / "..area)
  
  -- Normalize by height
  F:execute("Y = y/max(Y)")
end