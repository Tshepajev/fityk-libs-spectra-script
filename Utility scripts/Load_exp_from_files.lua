-- Lua script for Fityk.

name = "IWC_2_back_P"


strstart = "@+ < 'D:\\Research_analysis\\Projects\\2024_VTT\\JET_samples\\Stage_1\\Input_data_corrected\\"
batch = {
"1-100",
"1-100",
"1-100",
"1-50",
"1-20",
"1-5"
}
crater = {
3,
4,
5,
6,
7,
9
}

for i,v in ipairs(batch) do
	F:execute(strstart..name..crater[i].."_"..v..".txt':1:2..6::")
end