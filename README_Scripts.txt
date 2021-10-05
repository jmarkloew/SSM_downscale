following R scripts:

correlation with SWI: pixelwise correlation and linear regression (SWI ~ S1K0)
--> output: Korrelationsraster

regression: time-wise linear regression (SWI ~ S1K0 + additional data)
--> output: Regression: csv table with parameters
--> output: Residuals_raster: residuals per time and soil depth

random forest: time-wise random forest (SWI ~ S1K0 + additional data
--> output: RandomForest: csv tables with parameters + prediction maps


Attention: Scripts may not run from start till end. A lot of memory is needed for the calculations. 
Thus, the script may stop in the middle of the for loops. Just restart R and continue with the current soil depth.
