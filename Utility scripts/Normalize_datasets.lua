-- Lua script for Fityk.
-- Normalize all loaded datasets
datasetnr = F:get_dataset_count()
for i=0,datasetnr - 1 do
  F:execute("use @"..i)
  F:execute("Y = y/max(Y)")
end