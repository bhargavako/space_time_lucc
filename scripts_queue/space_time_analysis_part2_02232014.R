####################################    Space Time Analyses PAPER   #######################################
############################  Yucatan case study: ARIMA          #######################################
#This script produces a prediction for the dates following the Hurricane event.       
#                        
#AUTHORS: Benoit Parmentier                                             
#DATE CREATED: 11/27/2013 
#DATE MODIFIED: 02/20/2014
#Version: 2
#PROJECT: GLP Conference Berlin,YUCATAN CASE STUDY with Marco Millones             
#################################################################################################

###Loading R library and packages                                                      

library(sp)
library(rgdal)
library(BMS) #contains hex2bin and bin2hex
library(bitops)
library(gtools)
library(maptools)
library(parallel)
library(rasterVis)
library(raster)
library(forecast)
library(xts)
library(zoo)
library(lubridate)
library(colorRamps) #contains matlab.like color palette

###### Functions used in this script

raster_ts_arima<-function(pixel,na.rm=T,arima_order){
  arima_obj<-arima(pixel,order=arima_order)
  a<-as.numeric(coef(arima_obj)[1]) 
  return(a)
}

#This takes a pixel time series ... extracted from a stack
raster_ts_arima_predict <- function(pixel,na.rm=T,arima_order=NULL,n_ahead=2){
  if(is.null(arima_order)){
    arima_mod <- auto.arima(pixel)
    p_arima<- try(predict(arima_mod,n.ahead=n_ahead))
  }else{
    arima_mod<-arima(pixel,order=arima_order)
    p_arima<- try(predict(arima_mod,n.ahead=n_ahead))
  }
  if (!inherits(p_arima,"try-error")){
    y<- t(as.data.frame(p_arima$pred))
    y_error <- rep(0,n_ahead)
  }
  if (inherits(p_arima,"try-error")){
    y<- rep(NA,n_ahead)
    y_error <- rep(1,n_ahead)
  }
  pred_obj <- list(y,y_error)
  names(pred_obj)<-c("pred","error")
                                  
  return(pred_obj)
}

raster_NA_image <- function(r_stack){
  list_r_NA <- vector("list",length=nlayers(r_stack))
  for (i in 1:nlayers(r_stack)){
    r <- subset(r_stack,i)
    r_NA <- is.na(r)
    list_r_NA[[i]] <- r_NA
  }
  return(list_r_NA)
}

convert_arima_pred_to_raster <- function(i,list_param){
  #This function produces a raster image from ariam pred obj
  #Read in the parameters...
  r_ref <-list_param$r_ref
  ttx <- list_param$ttx
  file_format <- list_param$file_format
  out_dir <-list_param$out_dir
  out_rastname <-list_param$out_rastnames[i]
  file_format <- list_param$file_format
  NA_flag_val <- list_param$NA_flag_val
  
  #start script
  pred_t <- lapply(ttx,FUN=function(x){x$pred[i]})
  error_t <- lapply(ttx,FUN=function(x){x$error[i]})
  
  tt_dat <- do.call(rbind,pred_t)
  tt_dat <- as.data.frame(tt_dat)
  pred_t <-as(r_ref,"SpatialPointsDataFrame")
  pred_t <- as.data.frame(pred_t)
  pred_t <- cbind(pred_t,tt_dat)
  coordinates(pred_t) <- cbind(pred_t$x,pred_t$y)
  raster_pred <- rasterize(pred_t,r_ref,"V1",fun=mean)
  
  writeRaster(raster_pred,NAflag=NA_flag_val,filename=file.path(out_dir,out_rastname),
              overwrite=TRUE)  
  return(out_rastname)
}

#freq_r_stack(r_stack){
#  
#}

####### Parameters and arguments

## Location on Benoit's laptop (Dropbox)
#in_dir<- "/Users/benoitparmentier/Dropbox/Data/Space_Time"
in_dir<- "~/Documents/Data/Space_Time/"
#out_dir<- "/Users/benoitparmentier/Dropbox/Data/Space_Time"
out_dir<- "~/Documents/Data/Space_Time"

setwd(out_dir)
out_dir <- getwd() #to allow raster package to work...

function_analyses_paper <- "MODIS_and_raster_processing_functions_01252014.R"
script_path <- "~/Dropbox/Data/NCEAS/git_space_time_lucc/scripts_queue" #path to script functions
source(file.path(script_path,function_analyses_paper)) #source all functions used in this script.

#This is the shape file of outline of the study area                                                      #It is an input/output of the covariate script
infile_reg_outline <- "~/Documents/Data/Space_Time/GYRS_MX_trisate_sin_windowed.shp"  #input region outline defined by polygon: Oregon

#ref_rast_name<-""  #local raster name defining resolution, exent, local projection--. set on the fly?? 
ref_rast_name<-"~/Documents/Data/Space_Time/gyrs_sin_mask_1km_windowed.rst"  #local raster name defining resolution, exent: oregon
ref_samp4_name <-"~/Documents/Data/Space_Time/reg_Sample4.rst"
ref_sejidos_name <- "~/Documents/Data/Space_Time/00_sejidos_group_sel5_ids.rst"
ref_winds_name <- "~/Documents/Data/Space_Time/00_windzones_moore_sin.rst"
ref_EDGY_name <-"~/Documents/Data/Space_Time/reg_EDGY_mask_sin_1km.rst"
ref_egg_rings_gyr_name <-"~/Documents/Data/Space_Time/reg_egg_rings_gyr.rst"
infile_modis_grid<-"~/Documents/Data/Space_Time/modis_sinusoidal_grid_world.shp" #modis grid tiling system, global
proj_modis_str <-"+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181 +units=m +no_defs"
#CRS_interp <-"+proj=longlat +ellps=WGS84 +datum=WGS84 +towgs84=0,0,0" #Station coords WGS84
CRS_interp <- proj_modis_str
Moore_extent_name <- "~/Documents/Data/Space_Time/00_moore_clipped_sin_reduced.rst"
out_suffix <-"01252014" #output suffix for the files that are masked for quality and for 
    
## Other specific parameters
NA_flag_val<- -9999
file_format <- ".tif" #problem wiht writing IDRISI for hte time being
reg_var_list <- list.files(path=in_dir,pattern="reg_mosaiced_MOD13A2_A.*.__005_1_km_16_days_NDVI_09242013_09242013.rst$")
r_stack <- stack(reg_var_list)
levelplot(r_stack,layers=1:12) #show first 12 images (half a year more or less)

ref_rast_r  <- raster(ref_rast_name)
ref_samp4_r <- raster(ref_samp4_name)
mask_EDGY_r <- raster(ref_EDGY_name) #create raster image
egg_rings_gyr_r <- raster(ref_egg_rings_gyr_name)
moore_r <- raster(Moore_extent_name)
r_sejidos <- raster(ref_sejidos_name) 
r_winds <- raster(ref_winds_name) 

projection(mask_EDGY_r) <- proj_modis_str #assign projection coord defined earlier
projection(ref_samp4_r) <- proj_modis_str
projection(ref_rast_r) <- proj_modis_str
projection(egg_rings_gyr_r) <- proj_modis_str
projection(r_sejidos) <- proj_modis_str 
projection(r_winds) <- proj_modis_str 

r_x <- ref_rast_r #create raster image that will contain x coordinates
r_y <- ref_rast_r #create raster image that will contain y coordiates
values(r_x) <- coordinates(ref_rast_r)[,1] #set values in raster image to x coord
values(r_y) <- coordinates(ref_rast_r)[,2] #set values in raster image to y coord
pix_id_r <- ref_rast_r
values(pix_id_r) <- 1:ncell(ref_rast_r)
s_dat_var <-stack(pix_id_r,r_x,r_y,egg_rings_gyr_r,mask_EDGY_r,ref_samp4_r)
names(s_dat_var) <- c("pix_id_r","r_x","r_y","egg_rings_gyr_r",
                           "mask_EDGY_r","ref_samp4_r")
projection(s_dat_var) <- proj_modis_str
plot(s_dat_var)
s_dat_var <-stack(s_dat_var,r_sejidos,r_winds)
s_dat_var_m <- mask(s_dat_var,moore_r)
s_dat_var_m <- trim(s_dat_var_m)


################# PART 2: TEMPORAL PREDICTIONS ###################

#Hurricane August 17, 2007
day_event<-strftime(as.Date("2007.08.17",format="%Y.%m.%d"),"%j")
#153,154
names(r_stack)
grep(paste("2007",day_event,sep=""),names(r_stack))

### NOW ANALYSES WITH TIME AND SPACE...

## get small subset 1

# now extract these pixels and fit and arim for before period of hurricane
r_w <-raster("cropped_area.rst")
r_w_spdf <-as(r_w,"SpatialPointsDataFrame")
pix_val <- extract(r_stack,r_w_spdf,df=TRUE)

plot(as.numeric(pix_val[1,]),type="b")
abline(v=153,col="red") # Find out fire event in the area...there are some very low
#values that are not related to the hurricane...
plot(as.numeric(pix_val[1,139:161]),type="b")
abline(v=(154-139),col="red")

levelplot(r_stack,layer=152:155)
plot(subset(r_stack,154),legend=F)
plot(egg_rings_gyr_r,add=T,legend=F)
plot(ref_samp4_r,add=T,col=c("blue","red","black","yellow"))
plot(r_w,add=T,col="cyan",legend=F)
r_w_spdf<-as(r_w,"SpatialPointsDataFrame")

### Testing ARIMA model fitting with and without seasonality
#arima(USAccDeaths, order = c(0,1,1), seasonal = list(order=c(0,1,1)),
#plot(USAccDeaths)     
ts_x <- ts(data=pix_val[1,1:153],frequency=23) #frequency determines period...
frequency(ts_x) #frequency parameters is used in arima model fitting and spectrum
#acf(ts_x,lag.max=0,na.action=na.pass)

pacf(ts_x,na.action=na.pass)
acf(pix_val[1,1:153],na.action=na.pass) #wihtout a ts object
pacf(pix_val[1,1:153],na.action=na.pass)
#arima_mod <- auto.arima(ts_x)
#arima_mod <- auto.arima(pix_val[1,1:153])
arima_mod1 <- auto.arima(as.numeric(pix_val[1,1:153]))

#p_arima<-predict(arima_mod,n.ahead=2)
p_arima1<-predict(arima_mod1,n.ahead=2)

#arima_mod <- arima(pix_val[1,1:153], order = c(1,1,1), 
#                   seasonal = list(order=c(0,1,1)),
            
plot(as.numeric(pix_val[1,152:155]),type="b")
lines(c(as.numeric(pix_val[1,152:153]),p_arima$pred),type="b",col="red") #prediction with seasonality
lines(c(as.numeric(pix_val[1,152:153]),p_arima1$pred),type="b",col="blue")

raster_ts_arima(as.numeric(pix_val[1,1:153]),na.rm=T,c(1,0,0))                        
raster_ts_arima(as.numeric(pix_val[1,1:153]),na.rm=T,arima_order=c(0,0,2),n_ahead=2)                        

#Transform data to only include 1 to 153!!
pix <- as.data.frame(t(pix_val[,1:153]))

#acf(pix[1:153],na.action=na.pass)

tt<-raster_ts_arima_predict(pix[,1],na.rm=T,arima_order=NULL,n_ahead=2)
ttx<-lapply(pix,FUN=raster_ts_arima_predict,na.rm=T,arima_order=NULL,n_ahead=2)

tt_dat<-do.call(rbind,ttx)
class(tt_dat)

## Convert predicted values to raster...
r_pred_t1 <- r_w
r_pred_t2 <- r_w
values(r_pred_t1) <- as.numeric(unlist(tt_dat[,1]))
values(r_pred_t2) <- as.numeric(tt_dat[,2])

r_huric_w <- subset(r_stack,153:155)
r_huric_w <- crop(r_huric_w,r_w)

r_t0_pred <- stack(subset(r_huric_w,1),r_pred_t1,r_pred_t2)
names(r_t0_pred) <- c("NDVI_t_0","NDVI_pred_t_1","NDVI_pred_t_2")
dif_pred  <- r_t0_pred - r_huric_w 

#mfrow(c(2,3))
temp.colors <- colorRampPalette(c('blue', 'white', 'red'))
plot(stack(r_huric_w,r_t0_pred)) #compare visually predicted and actual NDVI
plot(dif_pred,col=temp.colors(25),colNA="black") #compare visually predicted and actual NDVI

sd_vals <- cellStats(dif_pred,"sd")
mean_vals <- cellStats(dif_pred,"mean")
#mode_vals <- cellStats(dif_pred,"mode")

hist(dif_pred)
dif_pred1 <-subset(dif_pred,2)
high_res<- dif_pred1>2*sd_vals[2] # select high residuals...
freq(high_res)

#There is large number of NA values after the hurricane
r_NA<-stack(raster_NA_image(r_huric_w))
freq(subset(r_NA,1)) # 10 NA cells
freq(subset(r_NA,2)) # 85 NA cells, after hurricane event...
freq(subset(r_NA,3)) # 26 NA cells


#### NOW do Moore area!! about 31,091 pixels

moore_r[moore_r==0]<- NA
moore_dat <- as(moore_r,"SpatialPointsDataFrame")
pix_val <- extract(r_stack,moore_dat,df=TRUE)
#pix_val <- t(pix_val[,1:153])
pix_val <- as.data.frame(t(pix_val[,1:153]))

#
ttx2 <- lapply(pix_val,FUN=raster_ts_arima_predict,na.rm=T,arima_order=NULL,n_ahead=2)
# <- mclapply(pix_val,,)
ttx2 <- mclapply(pix_val, FUN=raster_ts_arima_predict,na.rm=T,arima_order=NULL,n_ahead=2,mc.preschedule=FALSE,mc.cores = 3) #This is the end bracket from mclapply(...) statement


#
#ttx3 <- lapply(pix_val,FUN=raster_ts_arima_predict,na.rm=T,arima_order=c(1,0,1),n_ahead=2)
ttx3 <- mclapply(pix_val, FUN=raster_ts_arima_predict,na.rm=T,arima_order=c(1,0,1),n_ahead=2,mc.preschedule=FALSE, mc.cores = 3) #This is the end bracket from mclapply(...) statement

r_ref <- moore_r
file_format <- ".tif"
NA_flag_val <- -9999

out_rastnames <- paste(c("test_mooore1","test_moore2"),"_",out_suffix,file_format,sep="")
list_param_arima_convert <- list(r_ref,ttx2,file_format,out_dir,out_rastnames,file_format,NA_flag_val)
names(list_param_arima_convert) <- c("r_ref","ttx","file_format","out_dir","out_rastnames","file_format","NA_flag_val")

out_rastnames <- paste(c("test_mooore1_arima_101","test_moore2_arima_101"),"_",out_suffix,file_format,sep="")
#out_rastnames <- c("test_moore1_arima_1_0_1.rst","testmoore2_arima_1_0_1.rst")
list_param_arima_convert2 <- list(r_ref,ttx3,file_format,out_dir,out_rastnames,file_format,NA_flag_val)
names(list_param_arima_convert2) <- c("r_ref","ttx","file_format","out_dir","out_rastnames","file_format","NA_flag_val")

#debug(convert_arima_pred_to_raster)
## Convert predicted values to raster...

pred_t1 <- convert_arima_pred_to_raster(1,list_param=list_param_arima_convert)
pred_t2 <- convert_arima_pred_to_raster(2,list_param=list_param_arima_convert)

#Prediciton for arima 1,0,1
pred_t1_arima_101 <- convert_arima_pred_to_raster(1,list_param=list_param_arima_convert2)
pred_t2_arima_101 <- convert_arima_pred_to_raster(2,list_param=list_param_arima_convert2) #time step 2 after hurrincane

r_pred_t1 <- raster(pred_t1) #timestep 1
r_pred_t2 <- raster(pred_t2) #timestep 2

r_pred_t1_arima_101 <- raster(pred_t1_arima_101) #timestep 1
r_pred_t2_arima_101 <- raster(pred_t2_arima_101) #timestep 2

r_huric_w <- subset(r_stack,153:155)
#r_huric_w <- crop(r_huric_w,r_w)

r_t0_pred <- stack(subset(r_huric_w,1),r_pred_t1,r_pred_t2)
r_t0_pred_arima_101 <- stack(subset(r_huric_w,1),r_pred_t1_arima_101,
                             r_pred_t2_arima_101)
names(r_t0_pred) <- c("NDVI_t_0","NDVI_pred_t_1","NDVI_pred_t_2")
names(r_t0_pred_arima_101) <- c("NDVI_t_0","NDVI_pred_t_1","NDVI_pred_t_2")
dif_pred  <- r_t0_pred - r_huric_w #overprediction are positve and under prediction in negative
dif_pred_arima_101  <- r_t0_pred_arima_101 - r_huric_w #overprediction are positve and under prediction in negative

dif_pred_m <- mask(dif_pred,moore_r)
dif_pred_m <- trim(dif_pred_m)




plot(dif_pred_m)
#mfrow(c(2,3))


plot(stack(r_huric_w,r_t0_pred)) #compare visually predicted and actual NDVI
plot(dif_pred_m,col=matlab.like(25),colNA="black") #compare visually predicted and actual NDVI

dif_pred_pos <- dif_pred_m >0
dif_pred_neg <- dif_pred_m <0

freq(subset(dif_pred_pos,2)) #most of the pixels are over predicted!!!


plot(stack(dif_pred_pos,dif_pred_neg),col=matlab.like(25))

sd_vals <- cellStats(dif_pred,"sd")
mean_vals <- cellStats(dif_pred_m,"mean")
rmse_fun <-function(x){sqrt(mean(x^2,na.rm=TRUE))}
rmse_val <- cellStats(subset(dif_pred,2),"rmse_fun")

#mode_vals <- cellStats(dif_pred,"mode")

hist(dif_pred_m) #mostly positive
dif_pred1 <-subset(dif_pred_m,2)
high_res<- dif_pred1>2*sd_vals[2] # select high residuals...
freq(high_res)
plot(high_res) #high residuals...

## Calculate mean,MAE,RMSE residuals by zone of impact and ejidos
## plot average curve by zone of impact?


### Results for ARIMA 1,0,1
r_t0_pred <- stack(subset(r_huric_w,1),r_pred_t1_arima_101,r_pred_t2_arima_101)
names(r_t0_pred) <- c("NDVI_t_0","NDVI_pred_t_1","NDVI_pred_t_2")
dif_pred  <- r_t0_pred - r_huric_w #overprediction are positve and under prediction in negative

dif_pred_m <- mask(dif_pred,moore_r)
dif_pred_m <- trim(dif_pred_m)
plot(dif_pred_m)

plot(stack(r_huric_w,r_t0_pred)) #compare visually predicted and actual NDVI
plot(dif_pred_m,col=matlab.like(25),colNA="black") #compare visually predicted and actual NDVI

dif_pred_pos <- dif_pred_m >0
dif_pred_neg <- dif_pred_m <0

freq(subset(dif_pred_pos,2)) #most of the pixels are over predicted!!!

plot(stack(dif_pred_pos,dif_pred_neg),col=matlab.like(25))

sd_vals <- cellStats(dif_pred,"sd")
mean_vals <- cellStats(dif_pred_m,"mean")
rmse_vals <- cellStats(dif_pred_m,"rmse_fun")

rmse_fun <-function(x){sqrt(mean(x^2,na.rm=TRUE))}
mae_fun <-function(x){mean(abs(x),na.rm=TRUE)}

plot(r_w,add=T,col="cyan",legend=F)
r_w_spdf<-as(r_w,"SpatialPointsDataFrame")

#dif_pred_spdf <- as(dif_pred_m,"SpatialPointsDataFrame")
dif_df <- as.data.frame(dif_pred_m)

dif_df[,2]

rmse_fun(dif_df[,2])
rmse_fun(dif_df[,3])

mae_fun(dif_df[,2])
mae_fun(dif_df[,3])

rmse_val <- cellStats(subset(dif_pred,2),"rmse_fun")

############ Averages by rings of winds...

#...insert here
r_winds_m<-subset(s_dat_var_m,8)

avg_winds <- zonal(dif_pred_m,subset(s_dat_var_m,8))
mse_winds <- zonal(dif_pred_m,r_winds_m^2,fun="mean")
mae_winds <- zonal(dif_pred_m,abs(r_winds_m),fun="mean")
sqrt(mse_winds)
mae_winds
r_t0_pred

avg_winds_pred <- zonal(r_t0_pred_m,subset(s_dat_var_m,8))
mse_winds <- zonal(dif_pred_m,r_winds_m^2,fun="mean")
mae_winds <- zonal(dif_pred_m,abs(r_winds_m),fun="mean")

NA_val <- zonal(dif_pred_m,r_winds_m,fun="is.na")

#Ejidos

r_sejidos_m <-subset(s_dat_var_m,7)
avg_sejidos <- zonal(dif_pred_m,r_sejidos_m)
mse_sejidos <- zonal(dif_pred_m,r_sejidos_m^2,fun="mean")
sqrt(mse_sejidos)

r_t0_pred

###### Calculate Moran's I and first lag auto before and after event??

########### Compare RMSE and MAE for the predictions space and time...

