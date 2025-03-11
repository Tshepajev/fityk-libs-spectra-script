-- Lua script for Fityk.
-- Sums all datasets and creates a new one with that
function main()
	
	local datasetnr = F:get_dataset_count()
	local datasets_str = "@0"
	for i=1,datasetnr - 1 do
		datasets_str = datasets_str .. " + @" .. tostring(i)
	end
	
	F:execute("@+ = " .. datasets_str)
  
	print("Datasets sum done")
end
main()