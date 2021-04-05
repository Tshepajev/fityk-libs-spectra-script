-- Lua script for Fityk GUI version.
-- Script version: 1.8
-- Author: Jasper Ristkok

--[[
Written for use with LIBS (atomic) spectra gained from SOLIS software
with Andor iStar340T ICCD camera.
The script could possibly be used for other applications but some
adjustments to the code might be needed. Note that the script is
written for Fityk default settings (Fityk v 1.3.1).
There are comments to simplify understanding the code but
I assume assume that you have read the Fityk manual 
(http://fityk.nieto.pl/fityk-manual.html).

In Fityk the dataset to be plotted needs to be selected, 
however, selecting dataset for plotting is a GUI feature and is unavailable 
for scripts. Still, @0 is selected by default. Plotting uses this feature.
In case you can't get images drawn the right way, try to click 
dataset @0  in the data tab(so that it highlighted).

However, plotting uses the appearance that you have in the GUI.
Therefore, if you want datapoints to be connected with lines
you have to check "line" box in the GUI. Also if you make 1 dataset and
add nr_of_lines functions, you can colour them. These colours will
remain the same on drawn images. In other words: make 1 dataset the
way you want it to look, click on the dataset @0 and then run the script.
]]


-- CHANGE CONSTANTS BELOW!
----------------------------------------------------------------------
-- Constants, change them!

--Whether to use 387 nm parameters instead of 656 nm ones
is387=true

-- Where does the spectra actually start and end? (cutting away the edges) 
if is387 then
  start=435
  endpoint=1679
else
  start=417
  endpoint=1685
end

-- What are system paths for input and output folder?
-- Folders have to exist beforehand.
input_path="/Users/jasper/repos/fityk-libs-spectra-script/Examples/387nm_Mo_example/Input/"
output_path="/Users/jasper/repos/fityk-libs-spectra-script/Examples/387nm_Mo_example/Output/"

-- Change this if you want to use multiple instances of Fityk calculating
-- simultaneously using different inputs / different ranges. 
-- MAKE SURE THERE AREN'T ERRORS IN THE INPUT DATA
-- (input columns: file nr;pre-amp;exposure time;nr of accumulations;gain;gate width;
-- additional multiplier)
input_info_name="Info.csv"
-- (input columns: file nr;sensitivity;additional multiplier)
input_sensitivity_name="Sensitivity.csv"
output_data_name="Output.txt"

-- Filename for stopscript. If this file isn't empty then code stops loop after
-- processing current experiment and outputting data.
stopscript_name="Stopscript.txt"

-- What type of data files do you want to input?
file_end=".asc"

-- When importing text into spreadsheet filename (e.g. 13.5) may be 
-- read as a float. Using different separator (e.g. 13,5) avoids losing
-- "decimal" zeros from the end of the value
separator=","

-- To plot or not to plot [true/false]?
plot=true

-- What are the plotting ranges? Use false to use automatic ranges
-- e.g. x_min=false x_max=500 y_min=0.5 y_max=false
x_min=start-(endpoint-start)/10
x_max=endpoint+(endpoint-start)/10
y_min=false
y_max=false

-- If peak is considered wide then how wide is it? -- rudimentary
guess_initial_gwidth=25

-- Should the peaks be considered wide? -- rudimentary
wide=false

-- What is the minimal line gwidth? This will be Voigt functions' lower bound.
minimal_gwidth=0.5

-- Do you want to stop for query for continuing after every file? [true/false]
stop=false

-- How much do you want to lower constant upper bound according to equations
-- max=minimal_data_value+(median_data_value-minimal_data_value)*lower_constant
-- and
-- constant_value=(max+min)/2+(max-min)/2*sin(~angle)
-- or do you just want Fityk to guess constant height between min and median values 
-- (if former then recommended range is [0,1], if latter then write lower_constant=false).
lower_constant=0.1

-- How many spectra lines are there? Script checks this nr of elements in the next lists.
-- This means lists may be larger but not smaller than this.
if is387 then nr_of_lines=139
else nr_of_lines=159 end

-- Where are spectra lines in pixels? (only the first nr_of_lines lines are used)
-- By convention in lua, the first index is 1 instead of 0
if is387 then
  line_positions=
  {
  -- 387 nm
  -- Most intense peaks = I; Other intense peaks = O; 
  -- rest are smallest or unphysical, mathematical peaks
  441,  --1
  445,	--2
  449,  --3
  457,  --4
  465,  --5
  470,  --6
  476,	--7
  485,	--8
  489,  --9
  499,  --10
  509,  --11
  513,	--12
  518,	--13
  522,  --14    O
  528,  --15    O
  540,  --16
  545,  --17    O
  557,  --18
  564,	--19
  574,  --20
  579,  --21
  586,  --22
  591,  --23
  597,  --24
  603,  --25
  612,  --26    I
  633,  --27
  641,  --28
  648,  --29
  654,  --30
  659,	--31
  664,  --32
  671,	--33
  680,  --34
  685,  --35
  689,  --36    O
  699,  --37
  707,  --38
  715,  --39
  720,  --40
  725,  --41
  733,  --42
  751,  --43
  757,	--44
  762,  --45
  771,  --46
  783,  --47
  789,  --48
  795,  --49
  802,  --50    O
  810,  --51    O
  819,  --52    O
  830,  --53
  836,  --54
  844,  --55
  848,  --56
  857,  --57
  860,  --58
  867,  --59
  879,  --60
  886,  --61
  892,  --62
  900,  --63
  906,  --64
  912,  --65
  920,  --66
  931,	--67
  941,  --68    O
  951,  --69
  958,  --70
  965,  --71
  980,  --72    I
  989,	--73
  995,  --74
  1001, --75
  1008, --76
  1016, --77
  1022, --78    O
  1030, --79
  1037, --80
  1044,	--81
  1054,	--82
  1063, --83
  1075,	--84
  1081, --85   
  1090, --86
  1107, --87
  1115, --88
  1120,	--89
  1130, --90
  1136, --91
  1140,	--92
  1147, --93
  1162, --94
  1167, --95
  1191, --96
  1198, --97    I
  1210, --98
  1218, --99
  1228, --100   O
  1238, --101
  1249, --102
  1257, --103
  1268, --104   O
  1280,	--105
  1291, --106
  1301, --107
  1306, --108
  1314, --109
  1326, --110   O
  1339,	--111
  1346, --112
  1354, --113
  1369, --114
  1378, --115
  1388,	--116
  1401,	--117
  1413, --118   O
  1422, --119   O
  1428, --120
  1444, --121
  1450,	--122
  1467, --123
  1479, --124
  1492, --125
  1509, --126
  1526, --127   O
  1539, --128
  1547,	--129
  1564, --130   O
  1578,	--131
  1595, --132
  1611, --133
  1617, --134
  1623,	--135
  1629, --136
  1641, --137
  1647,	--138
  1663 --139    O
  }
else
  line_positions=
  {
  -- Most intense peaks 656nm  
  -- Other intense peaks
  -- Smaller intensity or mathematical peaks
  973,  --1  I  -- H-line
  420,  --2  O
  431,  --3
  438,  --4  O
  452,	--5
  459,	--6
  468,  --7 Mo2
  474,	--8
  482,	--9
  491,	--10
  503,  --11 Mo2
  511,  --12 O
  522,  --13
  529,  --14
  536,  --15
  547,  --16
  552,  --17 O
  562,  --18
  573,	--19
  584,	--20
  593,  --21
  603,	--22
  622,	--23
  628,  --24
  632,	--25
  639,	--26
  650,  --27 Mo2?
  657,	--28
  670,  --29
  697,  --30
  703,	--31
  709,  --32
  713,  --33 O
  734,  --34
  740,	--35
  746,  --36
  761,  --37
  767,  --38
  771,  --39
  793,	--40
  798,  --41
  807,  --42
  813,  --43
  821,	--44 
  826,	--45 
  832,	--46
  838,  --47
  845,  --48
  855,	--49
  864,	--50
  873,	--51
  878,  --52
  891,  --53
  901,	--54
  911,	--55
  916,	--56
  921,	--57
  927,	--58
  932,	--59
  937,	--60
  941,	--61
  946,	--62
  949,	--63
  954,  --64
  958,	--65
  965,	--66
  968,	--67
  974,  --68  extra line over H-line
  977,	--69
  983,	--70
  988,	--71
  992,  --72
  995,  --73
  999,	--74
  1003, --75
  1007,	--76
  1011,	--77
  1014,	--78
  1017,	--79
  1022, --80
  1029,	--81
  1044,	--82
  1048,	--83
  1052, --84
  1058,	--85
  1065, --86
  1077, --87
  1086,	--88
  1096,	--89
  1105,	--90
  1112, --91
  1117,	--92
  1121, --93
  1126,	--94
  1140, --95
  1143, --96 O
  1149,	--97
  1152,	--98
  1157,	--99
  1163,	--100
  1170,	--101
  1192,	--102
  1206,	--103
  1220, --104
  1226, --105
  1231,	--106
  1237,	--107
  1249, --108
  1252,	--109
  1256,	--110
  1262,	--111
  1266, --112 O
  1277,	--113
  1286,	--114
  1304,	--115
  1314, --116 I
  1324, --117
  1330, --118
  1337, --119
  1347, --120 O
  1354,	--121 O Mo2
  1363, --122 O
  1376,	--123
  1382,	--124
  1391, --125
  1394, --126
  1398, --127
  1404, --128
  1423, --129
  1435, --130
  1442, --131
  1451, --132
  1466, --133
  1470, --134
  1476, --135
  1483, --136
  1489, --137
  1496, --138
  1504, --139 I
  1512, --140
  1520,	--141
  1528, --142
  1544, --143
  1551,	--144
  1559, --145 O
  1563, --146
  1569,	--147
  1582, --148
  1587, --149
  1595, --150
  1599, --151
  1621, --152
  1630, --153
  1634,	--154 Mo2
  1645, --155
  1666, --156
  1674, --157
  1678, --158
  1682  --159
  }
end

-- How far can the peak shift? This will bind line to its location +/- radius 
-- defined here. Writing the value of the corresponding peak as -1 doesn't 
-- use script bounds (uses the Fityk's default 30% domain).
-- 0 locks the line in place
if is387 then
  line_center_domains=
  {
  3,  --1   387 nm
  3,  --2
  3,  --3
  3,  --4
  3,  --5
  3,  --6
  3,  --7
  3,  --8
  3,  --9
  3,  --10
  3,  --11
  3,  --12
  3,  --13
  3,  --14
  3,  --15
  3,  --16
  3,  --17
  3,  --18
  3,  --19
  3,  --20
  3,  --21
  3,  --22
  3,  --23
  3,  --24
  3,  --25
  3,  --26
  3,  --27
  3,  --28
  3,  --29
  3,  --30
  3,  --31
  3,  --32
  3,  --33
  3,  --34
  3,  --35
  3,  --36
  3,  --37
  3,  --38
  3,  --39
  3,  --40
  3,  --41
  3,  --42
  3,  --43
  3,  --44
  3,  --45
  3,  --46
  3,  --47
  3,  --48
  3,  --49
  3,  --50
  3,  --51
  3,  --52
  3,  --53
  3,  --54
  3,  --55
  3,  --56
  3,  --57
  3,  --58
  3,  --59
  3,  --60
  3,  --61
  3,  --62
  3,  --63
  3,  --64
  3,  --65
  3,  --66
  3,  --67
  3,  --68
  3,  --69
  3,  --70
  3,  --71
  3,  --72
  3,  --73
  3,  --74
  3,  --75
  3,  --76
  3,  --77
  3,  --78
  3,  --79
  3,  --80
  3,  --81
  3,  --82
  3,  --83
  3,  --84
  3,  --85
  3,  --86
  3,  --87
  3,  --88
  3,  --89
  3,  --90
  3,  --91
  3,  --92
  3,  --93
  3,  --94
  3,  --95
  3,  --96
  3,  --97
  3,  --98
  3,  --99
  3,  --100
  3,  --101
  3,  --102
  3,  --103
  3,  --104
  3,  --105
  3,  --106
  3,  --107
  3,  --108
  3,  --109
  3,  --110
  3,  --111
  3,  --112
  3,  --113
  3,  --114
  3,  --115
  3,  --116
  3,  --117
  3,  --118
  3,  --119
  3,  --120
  3,  --121
  3,  --122
  3,  --123
  3,  --124
  3,  --125
  3,  --126
  3,  --127
  3,  --128
  3,  --129
  3,  --130
  3,  --131
  3,  --132
  3,  --133
  3,  --134
  3,  --135
  3,  --136
  3,  --137
  3,  --138
  3,  --139
  3  --140
  }
else
  line_center_domains=
  {
  6,  --1
  3,  --2
  3,  --3
  3,  --4
  3,  --5
  3,  --6
  3,  --7
  3,  --8
  3,  --9
  3,  --10
  3,  --11
  3,  --12
  3,  --13
  3,  --14
  3,  --15
  2,  --16
  2,  --17
  3,  --18
  3,  --19
  3,  --20
  3,  --21
  3,  --22
  3,  --23
  2,  --24
  2,  --25
  3,  --26
  3,  --27
  3,  --28
  3,  --29
  2,  --30
  1,  --31
  1,  --32
  3,  --33
  3,  --34
  1.5,  --35
  1.5,  --36
  3,  --37
  3,  --38
  3,  --39
  3,  --40
  3,  --41
  3,  --42
  3,  --43
  1,  --44
  1,  --45
  2,  --46
  3,  --47
  3,  --48
  3,  --49
  3,  --50
  3,  --51
  3,  --52
  3,  --53
  3,  --54
  1.5,  --55
  1.5,  --56
  1.5,  --57
  1.5,  --58
  1.5,  --59
  1.5,  --60
  1.5,  --61
  1.5,  --62
  1.5,  --63
  1,  --64
  1,  --65
  1,  --66
  1,  --67
  1,  --68
  1,  --69
  1,  --70
  1,  --71
  1,  --72
  1.5,  --73
  1.5,  --74
  1.5,  --75
  1.5,  --76
  1.5,  --77
  1.5,  --78
  1.5,  --79
  1.5,  --80
  1.5,  --81
  3,  --82
  3,  --83
  3,  --84
  3,  --85
  3,  --86
  3,  --87
  3,  --88
  3,  --89
  3,  --90
  3,  --91
  3,  --92
  3,  --93
  3,  --94
  3,  --95
  3,  --96
  3,  --97
  3,  --98
  3,  --99
  3,  --100
  3,  --101
  3,  --102
  3,  --103
  3,  --104
  3,  --105
  3,  --106
  3,  --107
  3,  --108
  3,  --109
  3,  --110
  3,  --111
  3,  --112
  3,  --113
  3,  --114
  3,  --115
  3,  --116
  3,  --117
  3,  --118
  3,  --119
  3,  --120
  3,  --121
  3,  --122
  3,  --123
  3,  --124
  3,  --125
  3,  --126
  3,  --127
  3,  --128
  3,  --129
  3,  --130
  3,  --131
  3,  --132
  3,  --133
  3,  --134
  3,  --135
  3,  --136
  3,  --137
  3,  --138
  3,  --139
  3,  --140
  3,  --141
  3,  --142
  3,  --143
  3,  --144
  3,  --145
  3,  --146
  3,  --147
  3,  --148
  3,  --149
  3,  --150
  3,  --151
  3,  --152
  3,  --153
  3,  --154
  3,  --155
  3,  --156
  3,  --157
  3,  --158
  3,  --159
  3,  --160
  3,  --161
  3,  --162
  3,  --163
  3,  --164
  3,  --165
  3,  --166
  3,  --167
  3,  --168
  3,  --169
  3,  --170
  3,  --171
  3,  --172
  3,  --173
  3,  --174
  3,  --175
  3,  --176
  3,  --177
  3,  --178
  3,  --179
  3,  --180
  3,  --181
  3,  --182
  3,  --183
  3,  --184
  3,  --185
  3,  --186
  3,  --187
  3,  --188
  3,  --189
  3,  --190
  3,  --191
  3,  --192
  3,  --193
  3,  --194
  3,  --195
  3,  --196
  3,  --197
  3,  --198
  3,  --199
  3,  --200
  3,  --201
  3,  --202
  3,  --203
  3,  --204
  3,  --205
  3,  --206
  3,  --207
  3,  --208
  3,  --209
  3  --210
  }
end

-- Binds gwidths to given maximum gwidth. If corresponding gwidth
-- <=0 then doesn't bind line gwidth
if is387 then
  max_line_gwidths=
  {
  4,  --1  387 nm
  4,  --2
  4,  --3
  4,  --4
  4,  --5
  4,  --6
  4,  --7
  4,  --8
  4,  --9
  4,  --10
  4,  --11
  4,  --12
  4,  --13
  4,  --14
  4,  --15
  4,  --16
  4,  --17
  4,  --18
  4,  --19
  4,  --20
  4,  --21
  4,  --22
  4,  --23
  4,  --24
  4,  --25
  4,  --26
  4,  --27
  4,  --28
  4,  --29
  4,  --30
  4,  --31
  4,  --32
  4,  --33
  4,  --34
  4,  --35
  4,  --36
  4,  --37
  4,  --38
  4,  --39
  4,  --40
  4,  --41
  4,  --42
  4,  --43
  4,  --44
  4,  --45
  4,  --46
  4,  --47
  4,  --48
  4,  --49
  4,  --50
  4,  --51
  4,  --52
  4,  --53
  4,  --54
  4,  --55
  4,  --56
  4,  --57
  4,  --58
  4,  --59
  4,  --60
  4,  --61
  4,  --62
  4,  --63
  4,  --64
  4,  --65
  4,  --66
  4,  --67
  4,  --68
  4,  --69
  4,  --70
  4,  --71
  4,  --72
  4,  --73
  4,  --74
  4,  --75
  4,  --76
  4,  --77
  4,  --78
  4,  --79
  4,  --80
  4,  --81
  4,  --82
  4,  --83
  4,  --84
  4,  --85
  4,  --86
  4,  --87
  4,  --88
  4,  --89
  4,  --90
  4,  --91
  4,  --92
  4,  --93
  4,  --94
  4,  --95
  4,  --96
  4,  --97
  4,  --98
  4,  --99
  4,  --100
  4,  --101
  4,  --102
  4,  --103
  4,  --104
  4,  --105
  4,  --106
  4,  --107
  4,  --108
  4,  --109
  4,  --110
  4,  --111
  4,  --112
  4,  --113
  4,  --114
  4,  --115
  4,  --116
  4,  --117
  4,  --118
  4,  --119
  4,  --120
  4,  --121
  4,  --122
  4,  --123
  4,  --124
  4,  --125
  4,  --126
  4,  --127
  4,  --128
  4,  --129
  4,  --130
  4,  --131
  4,  --132
  4,  --133
  4,  --134
  4,  --135
  4,  --136
  4,  --137
  4,  --138
  4,  --139
  4  --140
  }
else
  max_line_gwidths=
  {
  40,  --1
  4,  --2
  4,  --3
  4,  --4
  4,  --5
  4,  --6
  4,  --7
  4,  --8
  4,  --9
  4,  --10
  4,  --11
  4,  --12
  4,  --13
  4,  --14
  4,  --15
  4,  --16
  4,  --17
  4,  --18
  4,  --19
  4,  --20
  4,  --21
  4,  --22
  4,  --23
  4,  --24
  4,  --25
  4,  --26
  4,  --27
  4,  --28
  4,  --29
  4,  --30
  4,  --31
  3.5,  --32
  4,  --33
  4,  --34
  4,  --35
  4,  --36
  4,  --37
  4,  --38
  4,  --39
  4,  --40
  4,  --41
  4,  --42
  4,  --43
  4,  --44
  4,  --45
  4,  --46
  4,  --47
  4,  --48
  4,  --49
  4,  --50
  4,  --51
  4,  --52
  4,  --53
  4,  --54
  4,  --55
  4,  --56
  4,  --57
  4,  --58
  4,  --59
  4,  --60
  4,  --61
  4,  --62
  4,  --63
  4,  --64
  4,  --65
  2,  --66
  2,  --67
  2,  --68
  2,  --69
  2,  --70
  4,  --71
  4,  --72
  4,  --73
  4,  --74
  4,  --75
  4,  --76
  4,  --77
  4,  --78
  4,  --79
  4,  --80
  4,  --81
  4,  --82
  4,  --83
  4,  --84
  4,  --85
  4,  --86
  4,  --87
  4,  --88
  4,  --89
  4,  --90
  4,  --91
  4,  --92
  4,  --93
  4,  --94
  4,  --95
  4,  --96
  4,  --97
  4,  --98
  4,  --99
  4,  --100
  4,  --101
  4,  --102
  4,  --103
  4,  --104
  4,  --105
  4,  --106
  4,  --107
  4,  --108
  4,  --109
  4,  --110
  4,  --111
  4,  --112
  4,  --113
  4,  --114
  4,  --115
  4,  --116
  4,  --117
  4,  --118
  4,  --119
  4,  --120
  4,  --121
  4,  --122
  4,  --123
  4,  --124
  4,  --125
  4,  --126
  4,  --127
  4,  --128
  4,  --129
  4,  --130
  4,  --131
  4,  --132
  4,  --133
  4,  --134
  4,  --135
  4,  --136
  4,  --137
  4,  --138
  4,  --139
  4,  --140
  4,  --141
  4,  --142
  4,  --143
  4,  --144
  4,  --145
  4,  --146
  4,  --147
  4,  --148
  4,  --149
  4,  --150
  4,  --151
  4,  --152
  4,  --153
  4,  --154
  4,  --155
  4,  --156
  4,  --157
  4,  --158
  4,  --159
  4,  --160
  4,  --161
  4,  --162
  4,  --163
  4,  --164
  4,  --165
  4,  --166
  4,  --167
  4,  --168
  4,  --169
  4,  --170
  4,  --171
  4,  --172
  4,  --173
  4,  --174
  4,  --175
  4,  --176
  4,  --177
  4,  --178
  4,  --179
  4,  --180
  4,  --181
  4,  --182
  4,  --183
  4,  --184
  4,  --185
  4,  --186
  4,  --187
  4,  --188
  4,  --189
  4,  --190
  4,  --191
  4,  --192
  4,  --193
  4,  --194
  4,  --195
  4,  --196
  4,  --197
  4,  --198
  4,  --199
  4,  --200
  4,  --201
  4,  --202
  4,  --203
  4,  --204
  4,  --205
  4,  --206
  4,  --207
  4,  --208
  4,  --209
  4  --210
  }
end
----------------------------------------------------------------------
-- CHANGE CONSTANTS ABOVE!


-- Global variable initializations
-- I know it's a bad habit... now, year after starting with the code
first_filenr=nil
last_filenr=nil
pre_amps=nil
exposures=nil
acc_nrs=nil
gains=nil
widths=nil
file_multipliers=nil
spectra_multiplier=nil

minimal_data_value=nil
median_data_value=nil
center_error="-"
constant_error=nil
center_errors={}
gwidth_errors={}
shape_errors={}
height_errors={}
file_check=nil
experiment_check=nil
stopscript=false

----------------------------------------------------------------------
--Function declarations
------------------------------------------
-- Deletes all variables
function delete_variables()
  variables=F:all_variables()
  for i=#variables-1,0,-1 do
    F:execute("delete $"..variables[i].name)
  end
end
------------------------------------------
-- Deletes all functions for dataset
function delete_functions(dataset_i)
  functions=F:get_components(dataset_i)
  for function_index=#functions-1,0,-1 do
    F:execute("delete %"..functions[function_index].name)
  end
end
------------------------------------------
-- Deletes dataset with given index, does NOT delete variables
function delete_dataset(dataset_i)
  delete_functions(dataset_i)
  -- Deletes the dataset
  F:execute("delete @"..dataset_i)
end
------------------------------------------
-- Deletes all datasets, functions and variables for clean sheet
-- equivalent to F:execute("reset")
function delete_all()
  -- Deletes datasets
  series_length=F:get_dataset_count()
  for dataset_i=series_length-1,0,-1 do
    F:execute("use @"..dataset_i)
    delete_dataset(dataset_i)
  end
  delete_variables()
end
------------------------------------------
-- Saves info file into separate arrays so that @0 is empty.
-- Loads info file for file-wise operations, 
-- (columns: file nr;pre-amp;exposure time;nr of accumulations;gain;
-- gate width;additional multiplier)
-- Additionally loads sensitivity info file for point-wise operations 
-- (columns: file nr;sensitivity;additional multiplier)
function load_info()
	-- Loads data from file info file (file-wise correction)
  F:execute("@+ < "..input_path..input_info_name..":1:2..::")
  -- Pre amplification
  pre_amp_data=F:get_data(0)
  -- Length of info file
  first_filenr=pre_amp_data[0].x
  last_filenr=pre_amp_data[#pre_amp_data-1].x
  -- Exposure times
  exposures_data=F:get_data(1)
  -- Nr. of accumulations
  accumulations_data=F:get_data(2)
  -- Gains
  gains_data=F:get_data(3)
  -- Gate widths
  widths_data=F:get_data(4)
  -- Additional multipliers
  additional_file_multipliers=F:get_data(5)
  -- Makes 6 arrays
  pre_amps={}
  exposures={}
  accumulations={}
  gains={}
  widths={}
  file_multipliers={}
  -- Iterates over all rows for file-wise data and saves data into lua arrays
  for row=0,#pre_amp_data-1,1 do
    pre_amps[row]=pre_amp_data[row].y
    exposures[row]=exposures_data[row].y
    accumulations[row]=accumulations_data[row].y
    gains[row]=gains_data[row].y
    widths[row]=widths_data[row].y
    file_multipliers[row]=additional_file_multipliers[row].y
  end
  -- Deletes info datasets
  F:execute("reset")
  
  -- Loads data from sensitivity info file (point-wise correction), 
  -- assumes that the first pixel is 0 like in the spectra
  F:execute("@+ < "..input_path..input_sensitivity_name..":1:2..::")
  -- Sensitivity data
  sensitivities=F:get_data(0)
  -- Additional point-wise multiplier - for backup
  additional_point_multipliers=F:get_data(1)
  -- Makes an array
  spectra_multiplier={}
  -- Iterates over all rows for point-wise data and saves data into lua arrays
  for row=0,#sensitivities-1,1 do
    spectra_multiplier[row]=sensitivities[row].y*additional_point_multipliers[row].y
  end
  -- Deletes info datasets
  F:execute("reset")
  
  -- Always uses only the first dataset (plotting hack).
  F:execute("use@0")
end
------------------------------------------
-- Initializes output file, change path if needed
function init_output()
  file=io.open(output_path..output_data_name,"w")
  io.output(file)
  io.write("Experiment nr")
  io.write("\tCHI^2")
  io.write("\tDegrees of freedom")
  io.write("\tConstant")
  io.write("\tConstant error")
  for i=1,nr_of_lines,1 do
    io.write("\tVoigt"..i.." height")
    io.write("\tVoigt"..i.." height error")
    io.write("\tVoigt"..i.." center")
    io.write("\tVoigt"..i.." center error")
    io.write("\tVoigt"..i.." gwidth")
    io.write("\tVoigt"..i.." gwidth error")
    io.write("\tVoigt"..i.." shape")
    io.write("\tVoigt"..i.." shape error")
    io.write("\tVoigt"..i.." Area")
    io.write("\tVoigt"..i.." FWHM")
    io.write("\tVoigt"..i.." GaussianFWHM")
    io.write("\tVoigt"..i.." LorentzianFWHM")
  end
  io.write("\n")
  io.close(file)
end
------------------------------------------
-- Data initialization before looping over datasets
function init_data1()
  if experiment_check then
    -- Loads 1 experiment from file
    F:execute("@+ <"..input_path..file_index..file_end..":1:"..(experiment_check+1).."::")
  else
    -- Loads 1 file. Change path if needed
    F:execute("@+ <"..input_path..file_index..file_end..":1:2..::")
  end
  -- Finds nr. of series in file
  series_length=F:get_dataset_count()
end
------------------------------------------
-- Data initialization while looping over datasets
function init_data2()  
	-- Loads data from info arrays for specific experiment file
	-- exposure_time=exposures[file_index-first_filenr]
	pre_amp=pre_amps[file_index-first_filenr]
	nr_of_accumulations=accumulations[file_index-first_filenr]
	gain=gains[file_index-first_filenr]
	gate_width=widths[file_index-first_filenr]
	additional_multiplier=file_multipliers[file_index-first_filenr]
	-- Calculates the real gain of the signal (from experiments)
	actual_gain=1.120270358187*math.exp(0.0019597049*gain)
	-- Compiles a constant to divide current spectrum with it
	multiplier=additional_multiplier/(pre_amp*gate_width*nr_of_accumulations*actual_gain)--/exposure_time
	
	-- Multiplies dataset with experiment parameters
	F:execute("Y=y*"..multiplier)
	
	-- Multiplies points in dataset with sensitivity and additional point-wise multipliers.
	-- Also does error catching in case input sensitivity has nil values.
  for row=0,#spectra_multiplier,1 do
    status, err = pcall(function()
      F:execute("Y["..row.."]=y["..row.."]*"..spectra_multiplier[row])
    end)
    if status == false then
      print("Error: " .. err)
    end
  end
	
	-- Cuts out the edges of the spectra
	F:execute("@0: A = a and not (-1 < x and x < "..start..")")
	F:execute("@0: A = a and not ("..endpoint.." < x and x < 2050)")
end
------------------------------------------
-- Subroutine for fit_functions()
-- Constructs string for parameters to be used with "guess Voigt"
function guess_parameter_constructor(linenr)
  local parameters="(center="
  -- Center
  if line_center_domains[linenr]==0 then
    -- Center is locked variable
    parameters=parameters..line_positions[linenr]
  elseif line_center_domains[linenr]<0 then
    -- Center is simple variable
    parameters=parameters.."~"..line_positions[linenr]
  else
    -- Angle variable
    F:execute("$center"..dataset_index.."_"..linenr.."=~0")
    -- Center is inside given domain e.g it's a compound variable
    -- center=line_position+domain*sin(~angle)
    parameters=parameters..line_positions[linenr].."+"..
      line_center_domains[linenr].."*sin($center"..dataset_index.."_"..linenr..")"
  end
  -- Shape
  -- Angle variable (3pi/2)
  F:execute("$shape"..dataset_index.."_"..linenr.."=~0")
  -- shape=0.5+0.5*sin(~ąngle) (binds it from 0 to 1)
  parameters=parameters..",shape=0.5+0.5*sin($shape"..dataset_index.."_"..linenr..")"
  
  -- Gwidth
  if max_line_gwidths[linenr]>0 then
    -- Angle variable starts from 3pi/2 so that sin is minimal
    F:execute("$gwidth"..dataset_index.."_"..linenr.."=~4.712")
    -- If there's substantial line broadening, guess wider functions
    if wide then
      -- gwidth=initial_gwidth+(initial_gwidth-min_gwidth)/2*(sin(~ąngle)-1)
      parameters=parameters..",gwidth="..guess_initial_gwidth.."+"..
        ((guess_initial_gwidth-minimal_gwidth)/2).."*(sin($gwidth"..
        dataset_index.."_"..linenr..")-1)"
    else
      -- gwidth=max_width+(max_width-min_width)/2*(sin(~ąngle)-1)
      parameters=parameters..",gwidth="..max_line_gwidths[linenr].."+"..
        ((max_line_gwidths[linenr]-minimal_gwidth)/2).."*(sin($gwidth"..
        dataset_index.."_"..linenr..")-1)"
    end
  end
  
  -- Maximum data value
  F:execute("$max_data_value=max(y if (x>"..start.." and x<"..endpoint.."))")
  max_data_value=F:get_variable("max_data_value"):value()
  
  -- Forces height to be positive
  F:execute("$height_variable"..dataset_index.."_"..linenr.."=~"..max_data_value)
  -- height=abs(height_variable)
  parameters=parameters..",height=abs($height_variable"..dataset_index.."_"..linenr..")"
  
  parameters=parameters..")"
  return parameters
end
------------------------------------------
-- Line fitting for 1 constant and nr_of_lines Voigt profiles
function fit_functions()
  -- Tries to account for wide H-line. The constant is bound between minimal data value
  -- and median data value. Otherwise constant is fitted too high because of wide H-line.
  -- Lowest constant bound
  F:execute("$min_data_value=min(y if (x>"..start.." and x<"..endpoint.."))")
  minimal_data_value=F:get_variable("min_data_value"):value()
  if minimal_data_value<0 then minimal_data_value=0 end
  -- Highest constant bound
  F:execute("$median_data_value=centile(50, y if (x>"..start.." and x<"..endpoint.."))")
  median_data_value=F:get_variable("median_data_value"):value()
  if median_data_value<0 then median_data_value=0 end
  -- Constant angle variable
  F:execute("$constant"..dataset_index.."=~0")
  
  -- if user wants then constant gets a value between certain relative value and 
  -- minimal data value
  if lower_constant then
    max_constant_value=minimal_data_value+(median_data_value-minimal_data_value)*lower_constant
    -- constant=(max+min)/2+(max-min)/2*sin(~angle)
    constant_parameters=((max_constant_value+minimal_data_value)/2).."+"..
      ((max_constant_value-minimal_data_value)/2).."*sin($constant"..dataset_index..")"
  -- Else binds constant to be fitted between median and minimal data value
  else
    -- constant=(median+min)/2+(median-min)/2*sin(~angle)
    constant_parameters=((median_data_value+minimal_data_value)/2).."+"..
      ((median_data_value-minimal_data_value)/2).."*sin($constant"..dataset_index..")"
  end
  F:execute("guess Constant(a="..constant_parameters..")")
  
  -- Iterates over lines
  for linenr=1,nr_of_lines,1 do
    -- Globalizes linenr from for loop for variable naming
    line_index=linenr
    guess_parameters=guess_parameter_constructor(line_index)
    -- Possible error catching (if peak outside of the range)
    status, err = pcall(function() F:execute("guess Voigt "..guess_parameters) end)    
    -- Catch error
    if (not status) then
      -- Make dummy function for indexing
      F:execute("guess Voigt (center="..line_positions[linenr]..",height=0)")
      print("Error: " .. err)
    end
  end
	
	-- Double fitting for against possible getting stuck in local minima
  F:execute("@0: fit")
  F:execute("@0: fit")
  print("Experiment: "..file_index..separator..dataset_index)
end
------------------------------------------
-- Saves line parameters' errors. It gets errors from $_variable.parameter.error.
-- I've concluded that this value is the standard error for that parameter.
function get_errors()
  -- y=a+b*sin(angle) => y_error=d_y/d_angle * angle_error
  -- y_error=b*cos(angle)*angle_error
  for linenr=1,nr_of_lines,1 do
    if functions[linenr]:get_param_value("height")>0 then
      -- Height
      -- y_error=height_error since abs value in the end gives the derivative as 1
      F:execute("$height_error=$height_variable"..dataset_index.."_"..linenr..".error")
      height_errors[linenr]=math.abs(F:get_variable("height_error"):value())
      
      -- Shape
      F:execute("$shape_error=$shape"..dataset_index.."_"..linenr..".error")
      shape_errors[linenr]=math.abs(0.5*math.cos(F:get_variable("shape"..dataset_index.."_"..linenr):value())
      *F:get_variable("shape_error"):value())
      
      -- Center
      if line_center_domains[linenr]>0 then
        F:execute("$center_error=$center"..dataset_index.."_"..linenr..".error")
        center_errors[linenr]=math.abs(line_center_domains[linenr]*math.cos(
        F:get_variable("center"..dataset_index.."_"..linenr):value())
        *F:get_variable("center_error"):value())
      end
      
      -- Gwidth
      if max_line_gwidths[linenr]>0 then
        if wide then
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=math.abs((guess_initial_gwidth-minimal_gwidth)/2*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value())
        else
          F:execute("$gwidth_error=$gwidth"..dataset_index.."_"..linenr..".error")
          gwidth_errors[linenr]=math.abs((max_line_gwidths[linenr]-minimal_gwidth)/2*math.cos(
          F:get_variable("gwidth"..dataset_index.."_"..linenr):value())
          *F:get_variable("gwidth_error"):value())
        end
      end
    end
  end
  -- dirty workaround to get constant standard error
	F:execute("$constant_error=$constant"..dataset_index..".error")
	constant_error=math.abs((median_data_value-minimal_data_value)/2*math.cos(
		F:get_variable("constant"..dataset_index):value())*
		F:get_variable("constant_error"):value())
end
------------------------------------------
-- Writes parameters of the functions into output file.
-- I've concluded that error values are standard errors.
function write_output()
  file=io.open(output_path..output_data_name,"a")
  io.output(file)
  -- Weighted sum of squared residuals, a.k.a. chi^2
  chi2=F:get_wssr(0)
  -- Degrees of freedom
  dof=F:get_dof(0)

  -- Writes dataset info
  io.write(file_index..separator..dataset_index)
  io.write("\t"..chi2)
  io.write("\t"..dof)
  io.write("\t"..functions[0]:get_param_value("a"))
  io.write("\t"..constant_error)
  -- loops over functions
  for i=1,nr_of_lines,1 do
    -- If there's no peak (peak height is 0) then all parameters are written "-"
    if (functions[i]:get_param_value("height")<=0) then
      io.write("\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-\t-")
    -- Else reads and writes peak info
    else
      -- shape_errors array comes from get_errors()
      shape_error=shape_errors[i]
  
      -- Checks center error from calculations
      -- If domains are specified then center_errors array comes from get_errors()
      if line_center_domains[i]<0 then
        F:execute("$center_error=F["..i.."].center.error")
        center_error=F:get_variable("center_error"):value()
      elseif line_center_domains[i]==0 then
        center_error="locked"
      else
        center_error=center_errors[i]
      end
      
      -- Checks gwidth error from calculations
      -- If max gwidth is specified then gwidth_errors array comes from get_errors()
      if max_line_gwidths[i]>0 then
        gwidth_error=gwidth_errors[i]
      else
        F:execute("$gwidth_error=F["..i.."].gwidth.error")
        gwidth_error=F:get_variable("gwidth_error"):value()
      end
      
      -- Height error isn't anymore a simple variable since I bound it to positive values
      height_error=height_errors[i]
      
      -- Writes data into file
      io.write("\t"..functions[i]:get_param_value("height"))
      -- standard error
      io.write("\t"..height_error)
      io.write("\t"..functions[i]:get_param_value("center"))
      -- standard error
      io.write("\t"..center_error)
      io.write("\t"..math.abs(functions[i]:get_param_value("gwidth")))
      -- standard error
      io.write("\t"..gwidth_error)
      io.write("\t"..math.abs(functions[i]:get_param_value("shape")))
      -- standard error
      io.write("\t"..shape_error)
      io.write("\t"..functions[i]:get_param_value("Area"))
      io.write("\t"..functions[i]:get_param_value("FWHM"))
      io.write("\t"..functions[i]:get_param_value("GaussianFWHM"))
      io.write("\t"..functions[i]:get_param_value("LorentzianFWHM"))
    end
  end    
  io.write("\n")
  io.close(file)
end
------------------------------------------
-- Draws a plot of the dataset @0 and all it's functions the way
-- it's rendered on the GUI
function plot_functions()
  -- Constructs plot command with correct ranges
  plot_command="plot ["
  if x_min then plot_command=plot_command..x_min end
  plot_command=plot_command..":"
  if x_max then plot_command=plot_command..x_max end
  plot_command=plot_command.."] ["
  if y_min then plot_command=plot_command..y_min end
  plot_command=plot_command..":"
  if y_max then plot_command=plot_command..y_max end
  plot_command=plot_command.."] @0 >> "..output_path..file_index..separator..dataset_index..".png"
  -- Draws an image from data and functions and saves it to output folder
  F:execute(plot_command)
end
----------------------------------------------------------------------
----------------------------------------------------------------------
-- MAIN PROGRAM
-- Loads data from files into memory, finds defined peaks, fits them,
-- exports the data and plots the graphs.

-- Cleans Fityk-side from everything. Equivalent to delete_all().
F:execute("reset")

-- Loads info and sensitivity into LUA arrays
load_info()

-- Asks whether to overwrite and start from scratch or just append
answer=F:input("Instead of overwriting, append to the output file? [y/n]")
if answer=='n' then 
  init_output()
end

-- Asks whether to use 1 experiment mode (good for debugging or line finding)
answer=F:input("Manually check 1 file? [y/n]")
if answer=='y' then 
  file_check=F:input("Number of file: ")
  experiment_check=F:input("Experiment number in the series: ")
end

-- Iterates over files
for n=first_filenr,last_filenr,1 do 
  -- Globalizes the for loop index and checks whether to view 1 file
  if file_check then 
    file_index=file_check
  else
    file_index=n
  end
  
  -- Loads all spectra from file (or 1 spectra if using 1 experiment mode)
  init_data1()
  
  -- Loops over datasets from file.
  for m=1,series_length,1 do
    -- Check whether user wants to stop the script while it's still running
    stopfile=io.open(input_path..stopscript_name,"r")
    io.input(stopfile)
    content=io.read()
    io.close(stopfile)
    if content then
      stopscript=true
      print("Stopping the script since "..stopscript_name.." isn't empty")
      break
    end
    
    -- Globalizes the for loop index
    dataset_index=m
  	
  	-- Processes spectra with info and sensitivity data
    init_data2()
    
    -- Generates and fits functions
    fit_functions()
    
    -- Finds dataset functions
    functions=F:get_components(0)
    
    -- Saves functions' errors into arrays
    get_errors()
    
    -- if using 1 experiment view then writes dataset index as the number for output
    if experiment_check then
      dataset_index=experiment_check
    end
    
    -- Writes data into output file
    write_output()  
    
    -- Plots current dataset with functions
    if plot then plot_functions() end
    
    if not experiment_check then
      delete_dataset(0)
      -- Deletes all variables. This wasn't done with deleting functions and
    	-- it kept hogging resources. Now long processes take c.a 60x less time
    	delete_variables()
    end
    
    print("Experiment: "..file_index..separator..dataset_index.." done.")
  end
  
  -- Stop the loop if using 1 experiment view or user wants to stop the script
  if file_check or stopscript then
    break
  end
  
  print("File nr "..file_index.." done.")
  
  -- Stop at current file for debugging
  if stop then
    answer=F:input("Stop at file "..file_index.."? [y/n]")
    if answer=='y' then 
      break
    end
  end
  
  
  -- Resets all Fityk-side info (not LUA-side, that holds all necessary info)
  F:execute("reset")
  
  --[[ Not needed anymore. Culprit of slowing down (and RAM hogging) was that 
  -- variables didn't get deleted with functions.
  -- Garbage collection
  -- https://stackoverflow.com/questions/28320213/why-do-we-need-to-call-luas-collectgarbage-twice
  collectgarbage("collect")
  collectgarbage("collect")
  print(collectgarbage("count"))
  --]]
end