library(rgdal)
library(raster)
library(RStoolbox)

setwd("D:/MedWater_Katrin/")

#load the aoi and buffer it (so that no pixels are lost when masking to aoi)
aoi <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped.shp")
aoi_buffer <- buffer(aoi, 0.1)
aoi_utm <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped_UTM_WGS_36N.shp")

#list all available swi files and extract date information from file name
swi_data <- data.frame(file = list.files("SWI_Daten/M0056793", pattern = ".nc$", recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
swi_data$date <- substr(swi_data$file, nchar(swi_data$file)-33, nchar(swi_data$file)-26)
#filter swi data: only files from 2016
swi_data <- swi_data[grepl("2016", swi_data$file),]

#list all available s1k0 files and extract date information from file name
s1k0_data <- data.frame(file = list.files("S_1_K0", pattern = glob2rx("*db*.tif$"), recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
s1k0_data$date <- lapply(s1k0_data$file, FUN = function(x){substr(strsplit(x, "/")[[1]][2],1,8)})
#filter s1k0 data: only files with fixed extent
s1k0_data <- s1k0_data[grepl("ext_fix", s1k0_data$file),]

#merge file information --> only dates left for which both data is available
merged_data <- merge(swi_data, s1k0_data, by = "date")

#load additional data
aspect <- brick("S_1_K0/additional_data/aspect_20_resample.tif")
convergence <- brick("S_1_K0/additional_data/convergence_index_20_resample.tif")
elevation <- brick("S_1_K0/additional_data/elevation_20_resample.tif")
slope <- brick("S_1_K0/additional_data/slope_deg_20_resample.tif")
twi <- brick("S_1_K0/additional_data/twi_20_resample.tif")
ndvi <- brick("S_1_K0/additional_data/NDVI_mean_and_stdev.tif")
names(ndvi) <- c("ndvi_mean","ndvi_sd")
ndwi <- brick("S_1_K0/additional_data/NDWI_mean_and_stdev.tif")
names(ndwi) <- c("nwdi_mean", "ndwi_sd")

#stack all additional data and remove single layers from memory
data_stack <- stack(aspect, convergence, elevation, slope, twi, ndvi, ndwi)
names(data_stack) <- c("aspect", "convergence", "elevation", "slope", "twi", "ndvi_mean", "ndvi_sd", "ndwi_mean", "ndwi_sd")
rm(aspect, convergence, elevation, slope, twi,ndvi, ndwi)

#create a template with size/extent of swi files
swi_template <- brick(merged_data$file.x[1], varname = "SWI_001")
proj4string(swi_template)<- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
swi_template <- crop(swi_template,aoi_buffer)
swi_template <- mask(swi_template, aoi_buffer)
swi_template <- projectRaster(swi_template, crs =("+proj=utm +zone=36 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0"))
swi_template <- mask(swi_template, aoi_utm)
swi_template <- resample(swi_template, data_stack, method = "ngb")
names(swi_template) <- "swi"

#create spatial points dataframe (all pixels of swi with data = 1 point) and randomly select 0.1% of the points
example_points <- rasterToPoints(swi_template, spatial = TRUE)
example_points <- example_points[sample(1:nrow(example_points), 0.001*nrow(example_points)),]

#--> these points are used for training/validation of the random forest for all soil depths
#--> data is saved in randomforest.RData 

#vector of all soil depths
varnames <- c("SWI_001", "SWI_005","SWI_010","SWI_015","SWI_020","SWI_040", "SWI_060", "SWI_100")
#varnames <- c("SWI_040")
#v <- varnames[1]

#do the following for all soil depths
for(v in varnames){
  print(v)
  #create  dataframe where all results are saved (rmse and r² of random forest and variable importance of all variables)
  model_output <- data.frame(date = merged_data$date, rmse_rf = NA, R2_rf = NA,
                             s1_k0_importance = NA, aspect_importance = NA, convergence_importance = NA, 
                             elevation_importance = NA, slope_importance = NA, twi_importance = NA,
                             ndvi_mean_importance = NA, ndvi_sd_importance = NA, ndwi_importance = NA,
                             ndwi_sd_importance = NA)
                             
  
  #i = 1
  #for each date do the following
  for(i in c(1:nrow(merged_data))){
    print(i)
    #load the swi layer of the specific date
    s1 <- brick(merged_data$file.y[i])
    names(s1) <- "s1_k0"
    
    #load the swi layer and mask and resample it to the aoi/s1k0 
    swi <- brick(merged_data$file.x[i], varname = v)
    proj4string(swi)<- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
    swi <- crop(swi,aoi_buffer)
    swi <- mask(swi, aoi_buffer)
    swi <- projectRaster(swi, crs =("+proj=utm +zone=36 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0"))
    swi <- mask(swi, aoi_utm)
    swi <- resample(swi, s1, method = "ngb")
    names(swi) <- "swi"
    
    #stack all predictor variable
    classification_stack <- stack(s1, data_stack)
    
    #extract the values of the swi values at the example points
    trainvals <- data.frame(extract(swi, example_points))
    names(trainvals) <- "swi"
    traindata <- example_points
    traindata@data <- trainvals
    
    #create the random forest
    rf1 <- superClass(img = classification_stack, trainData = traindata, trainPartition = 0.6, responseCol = "swi",
                      model = "rf", mode = "regression", predict = TRUE)
    #save the prediction map 
    writeRaster(rf1$map, paste0("S_1_K0/RandomForest/rf_prediction_", v, "_", merged_data$date[i], ".tif"), overwrite = TRUE)
    
    #extract the rmse, r² and variable importances of the random forest and the vairables
    rmse <- rf1$validation$performance$RMSE
    r2 <- rf1$validation$performance$Rsquared
    importances <- c(rf1$model$finalModel$importance)
    
    #save the parameters in the output dataframe
    model_output[i, c(2:ncol(model_output))] <- c(rmse, r2, importances)
    
    rm(s1, swi, classification_stack, trainvals, traindata, rmse, r2, importances, rf1)
  }
  
  #save the output dataframe
  write.csv(model_output, paste0("S_1_K0/RandomForest/model_output_", v, ".csv"))
}

