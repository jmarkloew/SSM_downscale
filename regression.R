library(rgdal)
library(raster)

setwd("D:/MedWater_Katrin/")

#load aoi and buffer (so that no pixels will be lost when masking to aoi)
aoi <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped.shp")
aoi_buffer <- buffer(aoi, 0.1)
aoi_utm <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped_UTM_WGS_36N.shp")

#list all available swi files and extract date information (from file name)
swi_data <- data.frame(file = list.files("SWI_Daten/M0056793", pattern = ".nc$", recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
swi_data$date <- substr(swi_data$file, nchar(swi_data$file)-33, nchar(swi_data$file)-26)
#filter swi files: only files from 2016
swi_data <- swi_data[grepl("2016", swi_data$file),]

#list all available s1k0 files and extract date information (from file name)
s1k0_data <- data.frame(file = list.files("S_1_K0", pattern = glob2rx("*db*.tif$"), recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
s1k0_data$date <- lapply(s1k0_data$file, FUN = function(x){substr(strsplit(x, "/")[[1]][2],1,8)})
#filter s1k0 data: only files with fixed extent
s1k0_data <- s1k0_data[grepl("ext_fix", s1k0_data$file),]

#merge the file information --> only dates left for which both data is available
merged_data <- merge(swi_data, s1k0_data, by = "date")

#load additional data and convert it to a large dataframe (one row = 1 pixel, each column for each data source)
#to save RAM: create the dataframe in two steps
#step 1: first half of the data
aspect <- brick("S_1_K0/additional_data/aspect_20_resample.tif")
convergence <- brick("S_1_K0/additional_data/convergence_index_20_resample.tif")
elevation <- brick("S_1_K0/additional_data/elevation_20_resample.tif")
slope <- brick("S_1_K0/additional_data/slope_deg_20_resample.tif")
add_data1 <- stack(aspect, convergence, elevation, slope)
names(add_data1) <- c("aspect", "convergence", "elevation", "slope")
rm(aspect, convergence, elevation, slope)
add_data1_vals <- data.frame(getValues(add_data1))
#step 2: second half of the data
twi <- brick("S_1_K0/additional_data/twi_20_resample.tif")
ndvi <- brick("S_1_K0/additional_data/NDVI_mean_and_stdev.tif")
ndvi_mean <- ndvi[[1]]
names(ndvi_mean) <- "ndvi_mean"
ndvi_sd <- ndvi[[2]]
names(ndvi_sd) <- "ndvi_sd"
ndwi <- brick("S_1_K0/additional_data/NDWI_mean_and_stdev.tif")
ndwi_mean <- ndwi[[1]]
names(ndwi_mean) <- "nwdi_mean"
ndwi_sd <- ndwi[[2]]
names(ndwi_sd) <- "ndwi_sd"
add_data2 <- stack(twi, ndvi_mean, ndvi_sd, ndwi_mean, ndwi_sd)
names(add_data2) <- c("twi", "ndvi_mean", "ndvi_sd", "ndwi_mean", "ndwi_sd")
rm(twi,ndvi, ndvi_mean, ndvi_sd, ndwi, ndwi_mean, ndwi_sd)
add_data2_vals <- data.frame(getValues(add_data2))

#combine the data
add_data_vals <- cbind(add_data1_vals, add_data2_vals)
rm(add_data1_vals, add_data2_vals)

#vector of all soil depths
varnames <- c("SWI_001", "SWI_005","SWI_010","SWI_015","SWI_020","SWI_040", "SWI_060", "SWI_100")
#varnames <- c("SWI_100")
#v <- varnames[1]


#do the following for all soil depths
for(v in varnames){
  #create a data frame where all results are saved (r² and p value of model, p value and coefficient estimate of all variables)
  model_output <- data.frame(date = merged_data$date, r2_model = NA, p_model = NA,
                              p_s1 = NA, p_aspect = NA,p_convergence = NA,p_elevation = NA,
                              p_slope = NA, p_twi = NA, p_ndvi_mean = NA,p_ndvi_sd = NA,
                              p_ndwi_mean = NA, p_ndwi_sd = NA, beta_s1 = NA,beta_aspect = NA, 
                              beta_convergence = NA,beta_elevation = NA,beta_slope = NA,
                              beta_twi = NA, beta_ndvi_mean = NA, beta_ndvi_sd = NA,
                              beta_ndwi_mean = NA,beta_ndwi_sd = NA)
  
  
  #i = 1
  #for each date, calculate a linear model
  for(i in c(1:nrow(merged_data))){
    print(i)
    #load the s1k0 layer of the specific date
    s1 <- brick(merged_data$file.y[i])
    names(s1) <- "s1_k0"
    
    #load the swi layer of the specific date and mask and resample to the aoi/s1k0 layer
    swi <- brick(merged_data$file.x[i], varname = v)
    proj4string(swi)<- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
    swi <- crop(swi,aoi_buffer)
    swi <- mask(swi, aoi_buffer)
    swi <- projectRaster(swi, crs =("+proj=utm +zone=36 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0"))
    swi <- mask(swi, aoi_utm)
    swi <- resample(swi, s1, method = "ngb")
    names(swi) <- "swi"
    
    #stack swi and s1k0 layers and extract data to data frame (same as above: 1 row = 1 pixel)
    data_stack <- stack(swi, s1)
    data_vals <- data.frame(getValues(data_stack))
    
    #combine the data with the dataframe with the additional data and remove rows/pixels with missing data (--> cannot be used for linear modelling)
    data_vals <- cbind(data_vals, add_data_vals)
    complete_rows <- complete.cases(data_vals)
    data_vals <- data_vals[complete.cases(data_vals),]
    
    #calculate linear model and extract the parameters
    model <- lm(swi ~., data = data_vals)
    r2 <- summary(model)$adj.r.squared
    p <- pf(summary(model)$fstatistic[1], summary(model)$fstatistic[2], summary(model)$fstatistic[3], lower.tail = FALSE)
    p_coeffs <- summary(model)$coefficients[2:nrow(summary(model)$coefficients),4]
    beta_coeffs <- summary(model)$coefficients[2:nrow(summary(model)$coefficients),1]
    
    model_vals <- c(r2, p, p_coeffs, beta_coeffs)
    
    #save the extracted parameters in the output dataframe
    model_output[i,2:ncol(model_output)] <- model_vals 
    
    #create an empty vector with the same length as the number of pixels in the swi layer
    residuals <- rep(NA, ncell(swi))
    #at the positions that are filled with data --> insert the models residuals
    residuals[complete_rows] <- model$residuals
    
    #convert the vector to a raster (with the swi layer as templat)
    residuals_r <- swi
    residuals_r[] <- residuals
    
    #if(i == 1){
    #   residual_stack <- residuals_r
    #}else{
    #   residual_stack <- stack(residual_stack, residuals_r)
    #}
    
    #write the residual raster to a Geotiff (specific date + specific soil depth)
    writeRaster(residuals_r, paste0("S_1_K0/Residuals_raster/residuals","_", v, "_", merged_data$date[i],".tif" ), overwrite = TRUE)
    rm(s1, swi, data_stack, data_vals, model, residuals, residuals_r)
    
  }
  #save the model parameters to a file (specific soil depth + all dates)
  write.csv(model_output, paste0("S_1_K0/Regression/model_output_", v, ".csv"))
}


