library(rgdal)
library(raster)

setwd("D:/MedWater_Katrin/")

#load aoi, buffer to make sure that by mask process no pixels get lost
aoi <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped.shp")
aoi_buffer <- buffer(aoi, 0.1)
aoi_utm <- readOGR("ISRAEL_WestBank_Western_Aquifer_Basin/Yarkon_Taninim_clipped_UTM_WGS_36N.shp")

#list all available swi files and extract date information (from file name)
swi_data <- data.frame(file = list.files("SWI_Daten/M0056793", pattern = ".nc$", recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
swi_data$date <- substr(swi_data$file, nchar(swi_data$file)-33, nchar(swi_data$file)-26)
#filter swi files: only SWI data from 2016
swi_data <- swi_data[grepl("2016", swi_data$file),]


#list all available s1k0 files and extract date information (from file name)
s1k0_data <- data.frame(file = list.files("S_1_K0", pattern = glob2rx("*db*.tif$"), recursive = TRUE, full.names = TRUE), stringsAsFactors = FALSE)
s1k0_data$date <- lapply(s1k0_data$file, FUN = function(x){substr(strsplit(x, "/")[[1]][2],1,8)})
#filter s1k0 data: only data with fixed extent
s1k0_data <- s1k0_data[grepl("ext_fix", s1k0_data$file),]

#merge file lists of swi and s1k0 data --> find dates for which both data is available
merged_data <- merge(swi_data, s1k0_data, by = "date")

#create a layer stack with all s1k0 data of the previous filtered dates
for(i in c(1:nrow(merged_data))){
  s1 <- brick(merged_data$file.y[i])
  if(i == 1){
    s1_stack <- s1
  }else{
    s1_stack <- stack(s1_stack, s1)
  }
  #layernames: date information
  names(s1_stack)[i] <- paste0("s1_k0_", merged_data$date[i])
  
}

#function to calculate correlation and linear regression
corr_lm_function <- function(x){
  #x <- as.vector(x)
  #pearson correlation coefficient
  c <- cor(x[1:23], x[24:46], method = "pearson")
  #create data frame so that one column = swi, another column = s1k0 values
  x_df <- data.frame(swi = x[1:23], s1 = x[24:46])
  #if there is no data for both of them --> no linear model can be calculated
  if(nrow(x_df[complete.cases(x_df),]) == 0){
    r2_mod <- NA
    p_mod <- NA
  }else{
    #calculate linear model (y = swi, x = s1k0)
    mod <- lm(swi ~ s1, data = x_df)
    #extract p value and R² of the model and return those
    p_mod <- as.numeric(pf(summary(mod)$fstatistic[1], summary(mod)$fstatistic[2], summary(mod)$fstatistic[3], lower.tail = FALSE))
    r2_mod <- summary(mod)$adj.r.squared
  }
  vals <- c(c, r2_mod, p_mod)
  return(vals)
}


#vector of all soil depths
varnames <- c("SWI_001", "SWI_005","SWI_010","SWI_015","SWI_020","SWI_040", "SWI_060", "SWI_100")
#varnames <- c("SWI_020")
#v <- varnames[1]

#do the following for all soil depths
for (v in varnames){
  print(paste("Processing", v))
  #create a layer stack of the swi data (of the specific soil depth) and mask it to the aoi
  for(i in c(1:nrow(merged_data))){
    swi <- brick(merged_data$file.x[i], varname = v)
    proj4string(swi)<- CRS("+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0")
    swi_aoi <- crop(swi,aoi_buffer)
    swi_aoi <- mask(swi_aoi, aoi_buffer)
    swi_aoi <- projectRaster(swi_aoi, crs =("+proj=utm +zone=36 +datum=WGS84 +units=m +no_defs +ellps=WGS84 +towgs84=0,0,0"))
    swi_aoi <- mask(swi_aoi, aoi_utm)
    if(i == 1){
      swi_stack <- swi_aoi
    }else{
      swi_stack <- stack(swi_stack, swi_aoi)
    }
    #layer names: date information
    names(swi_stack)[i] <- paste0("swi_", merged_data$date[i])
  }
  #resample swi stack to the extent of the s1k0 stack and stack them together
  swi_stack <- resample(swi_stack, s1_stack, method = "ngb")
  data_stack <- stack(swi_stack, s1_stack)
  
  #processing the whole raster stack at ones is too much for the local RAM 
  #--> do the calculations for a subset and merge it together later
  
  #row range for first subset (numbers are adapted to the exact size of the aoi)
  e1 <- 1
  e2 <- 2222
  
  #divide the raster stack in 5 subsets and do the calculations for all of them
  for (e in c(1:5)){
    print(e1)
    print(e2)
    #create the subset
    subset <- crop(data_stack,(extent(data_stack, e1,e2, 1, 4717)))
    #corr_raster_subset <- calc(subset, fun= function(x){cor(x[1:23], x[24:46])})
    #calculate the correlation/linear model
    corr_raster_subset <- calc(subset, fun= corr_lm_function)
    #move on to the next subset
    e1 <- e1 + 2222
    e2 <- e2 + 2222
    if(e == 4){
      e2 <- 11114
    }
    
    #merge the results of the single subsets
    if(e == 1){
      corr_raster <- corr_raster_subset
    }else{
      corr_raster <- merge(corr_raster, corr_raster_subset)
    }
    #names(corr_raster) <- c("pearson_corr", "r2_adj_lm", "p_lm")
  }
  
  #output raster: raster stack with layer 1 = pearson correlation between swi and s1k0, layer 2 = r² of linear model, layer 3 = p value of linear model
  writeRaster(corr_raster, paste0("S_1_K0/Regression/corr_lm_raster_", v, ".tif"), overwrite = TRUE)
  
  
}





