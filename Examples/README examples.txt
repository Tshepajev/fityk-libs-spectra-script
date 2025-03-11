Two examples are provided. 

First one, "656 nm with separate background" has relatively small spectrum (1024 px) with only few lines appearing in the series.
The input data files are Solis files which have many spectra in one file. 
The spectra aren't background corrected, so separate background spectra are provided.

The second example is for wide spectra (about 40 000 px) with many lines.
This is an extreme example which takes a long time to process (about 1.5 minutes per spectrum on Intel i5 processor)
The input data files are Sophi nXt files which have one spectrum per file. 
The example has only a few spectra to save space but I have processed 3000 of these in one series 
(and about 50 experiment series after that) with the same script.
The images are too crowded because of the view settings and the amount of lines used. 
In that case, it's best to save images without the line function labels but on the other hand, 
these are useful with the session files.
These spectra contain a few Be and Ar lines that experience Stark Shift - the line is shifted from its natural location.

Many images and sessions in output folder are deleted to save space in Github, 
but the ones left give the idea of the capabilities of the script.