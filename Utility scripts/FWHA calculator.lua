-- Lua script for Fityk.
-- Gets full width at half area from line
--input="/Users/jasper/Documents/Magistritöö/Andmetöötlus/2.etapp/Proge/Analyzer_input/Output656.txt"
--output="/Users/jasper/Documents/Magistritöö/Andmetöötlus/2.etapp/Proge/Analyzer_input/FWHA656.txt"

function load_info()
  -- Loads data from file info file (file-wise correction)
  F:execute("@+ < "..input..":0:7::")
  F:execute("@+ < "..input..":0:11::")
  F:execute("@+ < "..input..":0:13::")
  F:execute("@+ < "..input..":0:1::")
  F:execute("@+ < "..input..":0:2::")

  height_data=F:get_data(0)
  gwidth_data=F:get_data(1)
  shape_data=F:get_data(2)
  name_data1=F:get_data(3)
  name_data2=F:get_data(4)

  -- Makes arrays
  heights={}
  gwidths={}
  shapes={}
  names1={}
  names2={}
  
  -- Iterates over all rows for file-wise data and saves data into lua arrays
  for row=0,#height_data-1,1 do
    if row%6==0 then
      
    end
    heights[row]=height_data[row].y
    gwidths[row]=gwidth_data[row].y
    shapes[row]=shape_data[row].y
    names1[row]=name_data1[row].y
    names2[row]=name_data2[row].y
  end
  -- Deletes info datasets
  F:execute("reset")

  -- Always uses only the first dataset (plotting hack).
  F:execute("use@0")
end


F:execute("reset")

input="/Users/jasper/Documents/Magistritöö/Andmetöötlus/2.etapp/Proge/Analyzer_input/Output656.txt"
output="/Users/jasper/Documents/Magistritöö/Andmetöötlus/2.etapp/Proge/Analyzer_input/FWHA656.txt"

load_info()

--print(heights[1])
--print(#heights)

-- purge file
file=io.open(output,"w")
io.output(file)
--io.write("")
io.close(file)

file=io.open(output,"a")
io.output(file)
--io.write("a")


F:execute("%f=Voigt(center=1012,gwidth=1,height=1,shape=1)")
F:execute("F+=%f")

for row=0,#heights,1 do
  --row=379
  --print(names1[row]..","..names2[row])
  F:execute("%f=Voigt(center=1012,gwidth="..gwidths[row]..",height="..heights[row]..",shape="..shapes[row]..")")
  F:execute("M=2048;x=n;y=0")
  F:execute("Y=F(x)")
  


  F:execute("$start={y[0]}")
  F:execute("Y = y[n]+Y[n-1]")
  F:execute("Y = y[n]-2*$start")
  F:execute("$x=argmin(y if y > %f.Area*0.25)")
  x_min=F:get_variable("x"):value()
  F:execute("$x=argmin(y if y > %f.Area*0.75)")
  x_max=F:get_variable("x"):value()

  F:execute("$area=%f.Area/4")
  area=F:get_variable("area"):value()

  for i=x_min,(x_min-1),-0.01 do
    F:execute("$val={y["..i.."]}")
    val=F:get_variable("val"):value()
    if val<area then 
      x_min=i
      break
    end
  end

  area=area*3
  for i=x_max,(x_max),-0.01 do
    F:execute("$val={y["..i.."]}")
    val=F:get_variable("val"):value()
    if val<area then 
      x_max=i
      break
    end
  end

  --print(x_min)
  --print(x_max)
  --FWHA=(1012.79-x_val)*2
  FWHA=x_max-x_min
  print(FWHA)

  io.write(FWHA)
  io.write("\n")
  
end

io.close(file)