library(rgdal)
library(raster)
library(RStoolbox)
library(sp)

setwd("D:/Löw/MedWater/04_Additional_data/Katrin_Daten")

out_dir <- "SWI_Predictions"
query_dir <- dir.exists(out_dir)

if(query_dir==F) dir.create(out_dir)

aoi <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped.shp")
aoi_buffer <- buffer(aoi, 0.1)
aoi_utm <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped_UTM_WGS_36N.shp")

lulc <- raster("D:/Löw/MedWater/01_Land_use_classifcation/01_Sentinel-2/01_WAB_ISRAEL/01_DATA/01_2016_test_nsv_5_class_blackfoil_reaggregated_focal.tif")
my_quality_layer <- lulc
my_quality_layer[my_quality_layer %in% c(2,7)] <- 40 ## impervious surface+greenhouse near-zero prediction q
my_quality_layer[my_quality_layer %in% c(1,3)] <- 10 ## open soil good prediction q
my_quality_layer[my_quality_layer %in% c(4,5)] <- 20 ## changing vegetation cover moderate prediction q
my_quality_layer[my_quality_layer %in% c(6,9)] <- 30 ## dense vegetation cover bad prediction q
my_quality_layer[my_quality_layer == 8] <- -99 ## water bodies no prediction possible

lulc[lulc %in% c(2, 7,8)] <- NA
#list all available swi files and extract date information (from file name)
swi_data <- data.frame(file = list.files("SWI_Daten/M0056793", pattern = ".nc$", recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
swi_data$date <- substr(swi_data$file, nchar(swi_data$file)-33, nchar(swi_data$file)-26)
#filter swi files: only files from 2016
swi_data <- swi_data[grepl("2016", swi_data$file),]

varnames <- c("SWI_001", "SWI_005","SWI_010","SWI_015","SWI_020","SWI_040", "SWI_060", "SWI_100")

#list all available s1k0 files and extract date information (from file name)
s1k0_data <- data.frame(file = list.files("S_1_K0", pattern = glob2rx("*db*.tif$"), recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
s1k0_data$date <- lapply(s1k0_data$file, FUN = function(x){substr(strsplit(x, "/")[[1]][2],1,8)})

#merge the file information --> only dates left for which both data is available
merged_data <- merge(swi_data, s1k0_data, by = "date")

s1_stack <- stack(merged_data$file.y)

aspect <- brick("S_1_K0/additional_data/aspect_20_resample.tif")
convergence <- brick("S_1_K0/additional_data/convergence_index_20_resample.tif")
elevation <- brick("S_1_K0/additional_data/elevation_20_resample.tif")
slope <- brick("S_1_K0/additional_data/slope_deg_20_resample.tif")
twi <- brick("S_1_K0/additional_data/twi_20_resample.tif")
ndvi <- brick("S_1_K0/additional_data/NDVI_mean_and_stdev.tif")
ndwi <- brick("S_1_K0/additional_data/NDWI_mean_and_stdev.tif")

constant_stack <- stack(aspect, convergence, elevation, slope, twi, ndvi, ndwi)

i=15
k=2

resi_stack <- stack(list.files(path = "S_1_K0/Residuals_raster/raw_residuals", pattern = glob2rx(paste0("*", varnames[k], "*.tif$")), full.names = T))
resi_stack_masked <- mask(resi_stack, lulc)

writeRaster(resi_stack_masked, "temp_stack_masked.tif", format="GTiff", overwrite= T)

for (i in 15:nrow(merged_data)) {
  my_swi <- raster(merged_data$file.x[i], varname= varnames[k])
  my_resi <- brick("temp_stack_masked.tif")[[i]]
  my_k0 <- s1_stack[[i]]
  proj4string(my_swi)<- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
  swi <- crop(my_swi,aoi_buffer)
  swi <- mask(swi, aoi_buffer)
  swi <- projectRaster(swi, crs =("+proj=utm +zone=36 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0"))
  swi <- mask(swi, aoi_utm)
  swi <- resample(swi, s1_stack, method = "ngb")
  
  my_resi_rounded <- setValues(my_resi, round(getValues(my_resi), digits = 0))
  rm(my_resi)
  my_cellNR <- Which(my_resi_rounded %in% c(-2:2), cells=T)
  
  cellCoord <- xyFromCell(my_resi_rounded, my_cellNR)
  pos <- seq(1, nrow(cellCoord), 10)
  
  cellCoord_sub <- cellCoord[pos,]
  
  traincoords <- as.data.frame(cellCoord_sub)
  coordinates(traincoords) <- ~x+y
  crs(traincoords) <- crs(my_resi_rounded)
  
  traindata <- extract(swi, traincoords, sp=T)
  rm(traincoords)
  names(traindata) <- "swi"
  
  my_pred <- superClass(stack(my_k0, constant_stack), trainData = traindata, responseCol = "swi", trainPartition = 0.7,
                        model = "rf", mode = "regression", predict = TRUE, verbose = TRUE, kfold = 3, tuneLength = 1)
  
  my_out <- stack(my_pred$map, my_quality_layer)
  my_out_name <- paste0(out_dir, "/", s1k0_data$date[i], "_", varnames[k], "_lulc_adjusted_prediction.tif")
  
  writeRaster(my_out, filename = my_out_name, format="GTiff", overwrite=T)
}

file.remove("temp_stack_masked.tif")