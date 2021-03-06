####################################    Space Time Analyses PAPER   #######################################
############################  Yucatan case study: ARIMA          #######################################
#This script produces a prediction for the dates following the Hurricane event.       
#Predictions are done with ARIMA model leveraging temporal correlation.                        
#AUTHORS: Benoit Parmentier                                             
#DATE CREATED: 11/27/2013 
#DATE MODIFIED: 03/12/2015
#Version: 4
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

#This is the main function!!!
raster_ts_arima_predict <- function(i,list_param){
  
  #extract parameters                                  
  pixel <-list_param$pix_val[i]
  arima_order <-list_param$arima_order
  n_ahead <- list_param$n_ahead
  out_suffix <- list_param$out_suffix
  na.rm=T

  #Start

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
  save(arima_mod,file=paste("arima_mod_",i,out_suffix,".RData",sep=""))             
  
  return(pred_obj)
}



pixel_ts_arima_predict <- function(i,list_param){
  
  #extract parameters                                  
  pixel <-list_param$pix_val[i]
  arima_order <-list_param$arima_order
  n_ahead <- list_param$n_ahead
  out_suffix <- list_param$out_suffix
  na.rm=T

  #Start

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
  save(arima_mod,file=paste("arima_mod_",i,out_suffix,".RData",sep=""))             
  
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
  out_suffix <- list_param$out_suffix
  out_rastname <-list_param$out_rastnames[i]
  file_format <- list_param$file_format
  NA_flag_val <- list_param$NA_flag_val
  
  #start script
  #pred_t <- lapply(ttx,FUN=function(x){x$pred[i]})
  #error_t <- lapply(ttx,FUN=function(x){x$error[i]})
  
  l_r <-vector("list", length=2)
  l_r[[1]]<-lapply(ttx,FUN=function(x){x$pred[i]})
  l_r[[2]] <- lapply(ttx,FUN=function(x){x$error[i]})
  
  for (j in 1:2){
    tt_dat <- do.call(rbind,l_r[[j]])
    tt_dat <- as.data.frame(tt_dat)
    pred_t <-as(r_ref,"SpatialPointsDataFrame")
    pred_t <- as.data.frame(pred_t)
    pred_t <- cbind(pred_t,tt_dat)
    coordinates(pred_t) <- cbind(pred_t$x,pred_t$y)
    raster_pred <- rasterize(pred_t,r_ref,"V1",fun=mean)
    l_r[[j]] <- raster_pred
  }
  
  #tmp_name <- extension(out_rastname)
  #modify output name to for error image
  tmp_name <- unlist(strsplit(out_rastname,"_"))
  nb<- length(tmp_name)
  tmp_name <-paste(paste(tmp_name[1:(nb-1)],collapse="_"),
             "error",tmp_name[nb],sep="_")
  writeRaster( l_r[[2]],NAflag=NA_flag_val,
              filename=file.path(out_dir,tmp_name),
              overwrite=TRUE)  
  writeRaster( l_r[[1]],NAflag=NA_flag_val,
              filename=file.path(out_dir,out_rastname),
              overwrite=TRUE)  
  return(list(out_rastname,tmp_name))
}

create_dir_fun <- function(out_dir,out_suffix){
  if(!is.null(out_suffix)){
    out_name <- paste("output_",out_suffix,sep="")
    out_dir <- file.path(out_dir,out_name)
  }
  #create if does not exists
  if(!file.exists(out_dir)){
    dir.create(out_dir)
  }
  return(out_dir)
}

load_obj <- function(f){
  env <- new.env()
  nm <- load(f, env)[1]
  env[[nm]]
}

extract_arima_mod_info <- function(i,list_param){
  fname <- list_param$arima_mod_name[i]
  arima_mod <- load_obj(fname)
  #summary(arima_mod)
  #coef(arima_mod)
  arima_specification <- arima_mod$arma
  arima_coef <-  coef(arima_mod)
  #http://stackoverflow.com/questions/19483952/how-to-extract-integration-order-d-from-auto-arima
  #a$arma[length(a$arma)-1] is the order d
  #[1] 2 0 0 0 1 0 0
  #A compact form of the specification, as a vector giving the number of AR (1), MA (2), 
  #seasonal AR (3) and seasonal MA coefficients (4), 
  #plus the period (5) and the number of non-seasonal (6) and seasonal differences (7).
  
  return(list(arima_specification,arima_coef))
} 

################### Parameters and arguments #################

###### Functions used in this script

function_spatial_regression_analyses <- "SPatial_analysis_spatial_reg_02262015_functions.R"
function_analyses_paper <- "MODIS_and_raster_processing_functions_04172014.R"

script_path <- "/home/parmentier/Data/Space_beats_time/sbt_scripts" #path to script

#script_path <- "/home/parmentier/Data/Space_beats_time/R_Workshop_April2014/R_workshop_WM_04232014" #path to script
source(file.path(script_path,function_spatial_regression_analyses)) #source all functions used in this script 1.

#script_path <- "~/Dropbox/Data/NCEAS/git_space_time_lucc/scripts_queue" #path to script functions
script_path <- file.path(in_dir,"R") #path to script functions

source(file.path(script_path,function_analyses_paper)) #source all functions used in this script.

###### Functions used in this script

function_spatial_regression_analyses <- "SPatial_analysis_spatial_reg_03092015_functions.R"
script_path <- "/home/parmentier/Data/Space_beats_time/sbt_scripts" #path to script
#script_path <- "/home/parmentier/Data/Space_beats_time/R_Workshop_April2014/R_workshop_WM_04232014" #path to script
source(file.path(script_path,function_spatial_regression_analyses)) #source all functions used in this script 1.

#####  Parameters and argument set up ###########

#This is the shape file of outline of the study area    
#ref_rast_name<-file.path(in_dir,"/reg_input_yucatan/gyrs_sin_mask_1km_windowed.rst")  #local raster name defining resolution, exent: oregon

#infile_modis_grid <- file.path(in_dir,"/reg_input_yucatan/modis_sinusoidal_grid_world.shp")

#create_out_dir_param <- TRUE #create output directory using previously set out_dir and/or out_suffix
#It is an input/output of the covariate script
#infile_reg_outline <- "~/Data/Space_Time/GYRS_MX_trisate_sin_windowed.shp"  #input region outline defined by polygon: Oregon
## Other specific parameters
#NA_flag_val<- -9999
#file_format <- ".rst" #problem wiht writing IDRISI for hte time being
#create_out_dir_param <- FALSE

in_dir<-"~/Data/Space_beats_time/Case1a_data"
out_dir <- "/home/parmentier/Data/Space_beats_time/output_EDGY_predictions_03092015"
in_dir_NDVI <- file.path(in_dir,"moore_NDVI_wgs84") #contains NDVI 
  
moore_window <- file.path(in_dir,"window_test4.rst") #spatial subset of Moore region to test spatial regression
winds_zones_fname <- file.path(in_dir,"00_windzones_moore_sin.rst")

proj_modis_str <-"+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +a=6371007.181 +b=6371007.181 +units=m +no_defs"
#CRS_interp <-"+proj=longlat +ellps=WGS84 +datum=WGS84 +towgs84=0,0,0" #Station coords WGS84
CRS_WGS84 <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +towgs84=0,0,0" #Station coords WGS84
proj_str<- CRS_WGS84
CRS_interp <- proj_modis_str

file_format <- ".rst" #raster format used
NA_value <- -9999
NA_flag_val <- NA_value
num_cores <- 9

out_suffix <-"EDGY_predictions_03092015" #output suffix for the files that are masked for quality and for 
create_out_dir_param=FALSE

############################  START SCRIPT ###################

### PART I READ AND PREPARE DATA FOR REGRESSIONS #######
#set up the working directory
#Create output directory

#out_dir <- in_dir #output will be created in the input dir
out_dir <- dirname(in_dir) #get parent dir where the output will be created..

out_suffix_s <- out_suffix #can modify name of output suffix
if(create_out_dir_param==TRUE){
  out_dir <- create_dir_fun(out_dir,out_suffix_s)
  setwd(out_dir)
}else{
  setwd(out_dir) #use previoulsy defined directory
}
#EDGY_dat_spdf_04072014.txt
#data_fname <- file.path("/home/parmentier/Data/Space_beats_time/R_Workshop_April2014","Katrina_Output_CSV - Katrina_pop.csv")
data_fname <- file.path(in_dir,"EDGY_dat_spdf_04072014.txt") #contains the whole dataset

data_tb <-read.table(data_fname,sep=",",header=T)
dim(data_tb) #shows the dimensions: 26,216x283

#### Make this a function...

#Transform table text file into a raster image
#coord_names <- c("XCoord","YCoord") #for Katrina
coord_names <- c("r_x","r_y") #coordinates for EDGY dataset

#Create raster images from the text file...
#l_rast <- rasterize_df_fun(data_tb[,1:5],coord_names,proj_str,out_suffix,out_dir=".",file_format,NA_flag_val)
l_rast <- rasterize_df_fun(data_tb,coord_names,proj_str,out_suffix,out_dir=".",file_format,NA_flag_val)

#debug(rasterize_df_fun)
s_raster <- stack(l_rast) #stack with all the variables
names(s_raster) <- names(data_tb)                

r_FID <- raster(l_rast[1])
plot(r_FID,main="Pixel ID")
freq(r_FID)
dim(s_raster) #128x242x283 (var 283)
ncell(s_raster) #30,976
freq(r_FID,value=NA) #4760
ncell(s_raster) - freq(r_FID,value=NA) #26216
freq(subset(s_raster,"NDVI_1"),value=NA) #4766

################# PART 1: TEMPORAL PREDICTIONS ###################

NDVI_names <- paste("NDVI",1:273,sep="_")
r_stack <- subset(s_raster,NDVI_names)
#Hurricane August 17, 2007
#day_event<-strftime(as.Date("2007.08.17",format="%Y.%m.%d"),"%j")
#153,154
names(r_stack)

#grep(paste("2007",day_event,sep=""),names(r_stack))

#r_huric_w <- mask(r_huric_w,moore_w)

#r_stack_w <- mask(r_stack,rast_ref)
levelplot(r_stack,layers=153:154,col.regions=matlab.like(125)) #show first 2 images (half a year more or less)
plot(r_stack,y=153:154)
histogram(subset(r_stack,153:154))
rast_ref <- subset(s_raster,1) #first image ID

r_stack <- mask(r_stack,rast_ref)

#### Use ARIMA FUNCTION TO PREDICT...
#### Now do Moore area!! about 31,091 pixels

#pix_val <- as(r_stack_w,"SpatialPointsDataFrame")
pix_val <- as(r_stack,"SpatialPointsDataFrame")

#pix_val <- as.data.frame(r_stack_w)
#moore_dat <- as(moore_w,"SpatialPointsDataFrame")
#r_huric_w <- subset(r_stack_w,152:156) #date before hurricane and  after

#pix_val <- extract(r_stack,moore_dat,df=TRUE)
#pix_val <- t(pix_val[,1:153])
pix_val2 <- as.data.frame(pix_val)
pix_val2 <-  pix_val2[,1:152] 
pix_val2 <- as.data.frame(t(as.matrix(pix_val2 )))#dim 152x26,616

### Should add a window option to subset the pixels time series
#
#ttx2 <- lapply(pix_val,FUN=raster_ts_arima_predict,na.rm=T,arima_order=NULL,n_ahead=2)
# <- mclapply(pix_val,,)

n_pred_ahead <- 4 #number of temporal ARIMA predictions ahead..

## Now prepare predictions: should this a be a function?

list_param_predict_arima_2 <- list(pix_val=pix_val2,na.rm=T,arima_order=NULL,n_ahead=n_pred_ahead)
#undebug(pixel_ts_arima_predict)
tmp_val <- raster_ts_arima_predict(1,list_param_predict_arima_2)
#started at 6.34 on Sat 14
arima_pixel_pred_obj <- mclapply(1:length(pix_val2), FUN=pixel_ts_arima_predict,list_param=list_param_predict_arima_2,mc.preschedule=FALSE,mc.cores = 11) 
save(arima_pixel_pred_obj,file=paste("arima_pixel_pred_obj",out_suffix,".RData",sep=""))
##Finished at
#ttx3 <- load_obj("raster_ts_arima_predict_obj04212014.RData")
#ttx2 <- mclapply(1:length(pix_val), FUN=raster_ts_arima_predict,list_param=list_param_predict_arima_2,mc.preschedule=FALSE,mc.cores = 12) #This is the end bracket from mclapply(...) statement
#ttx2 <- lapply(1:length(pix_val2), FUN=raster_ts_arima_predict,list_param=list_param_predict_arima_2) #This is the end bracket from mclapply(...) statement

#file_format <- ".rst"
#NA_flag_val <- -9999
#rast_ref <- rast_ref != NA_flag_val
#pix_id_r <- rast_ref
#values(pix_id_r) <- 1:ncell(rast_ref) #create an image with pixel id for every observation
#pix_id_r <- mask(pix_id_r,rast_ref) #3854 pixels from which 779 pixels are NA
r_ref <- rast_ref

out_rastnames <- paste(paste("NDVI_pred_mooore_auto",1:n_pred_ahead,sep="_"),"_",out_suffix,file_format,sep="")
list_param_arima_convert <- list(rast_ref,arima_pixel_pred_obj,file_format,out_dir,out_rastnames,file_format,NA_flag_val)
names(list_param_arima_convert) <- c("r_ref","ttx","file_format","out_dir","out_rastnames","file_format","NA_flag_val")

#debug(convert_arima_pred_to_raster)
## Convert predicted values to raster...

pred_t_l<-lapply(1:n_pred_ahead,FUN=convert_arima_pred_to_raster,list_param=list_param_arima_convert) #,mc.preschedule=FALSE,mc.cores = num_cores)
#pred_t_l<-mclapply(1:n_pred_ahead,FUN=convert_arima_pred_to_raster,list_param=list_param_arima_convert,mc.preschedule=FALSE,mc.cores = num_cores)

#arima_pixel_pred_obj <- mclapply(1:length(pix_val2), FUN=pixel_ts_arima_predict,list_param=list_param_predict_arima_2,mc.preschedule=FALSE,mc.cores = num_cores) 

pred_t_l <-unlist(pred_t_l)
r_pred  <- stack(pred_t_l[-c(grep(pattern="error",pred_t_l))])
r_error <- stack(pred_t_l[c(grep(pattern="error",pred_t_l))])

r_huric_w <- subset(r_stack,153:156)
#r_huric_w <- crop(r_huric_w,moore_w)

r_t0_pred <- stack(subset(r_huric_w,1),r_pred_t1,r_pred_t2)
names(r_t0_pred) <- c("NDVI_t_0","NDVI_pred_t_1","NDVI_pred_t_2")

#### Analyses of Model fitted...

l_arima_mod <- list.files(path=out_dir,pattern="arima_mod.*.RData",full.names=T)
test_arima_mod_obj<-load_obj(l_arima_mod[[1]])

list_param_extract_arima <- list(arima_mod_name=l_arima_mod)

#debug(extract_arima_mod_info)
test <- extract_arima_mod_info(1,list_param_extract_arima)

#tmp_val <- raster_ts_arima_predict(1,list_param_predict_arima_2)
l_arima_info <- mclapply(1:length(l_arima_mod), FUN=extract_arima_mod_info,list_param=list_param_extract_arima,
                         mc.preschedule=FALSE,mc.cores = 11) #This is the end bracket from mclapply(...) statement


save(l_arima_info,file=paste("l_arima_info_obj",out_suffix,".RData",sep=""))
#l_arima_info <-load_obj("l_arima_mod_info_obj04212014.RData")
#mod_specification <- mclapply(l_arima_info[1:11],FUN=function(i){i[[1]]},mc.preschedule=FALSE,mc.cores = 11)
#test_name <- list.files(".","l_arima_mod_info_obj.*.RData")
mod_specification <- mclapply(l_arima_info,FUN=function(i){i[[1]]},mc.preschedule=FALSE,mc.cores = 11)
mod_specification2 <- mod_specification[1:26216]
#[1] 2 0 0 0 1 0 0
#A compact form of the specification, as a vector giving the number of AR (1), MA (2), 
#seasonal AR (3) and seasonal MA coefficients (4), 
#plus the period (5) and the number of non-seasonal (6) and seasonal differences (7).

fitted_mod_spec <- as.data.frame(do.call(rbind,mod_specification2))
#should add  id or coordinates!!!!so you can map it!!
names(fitted_mod_spec) <- c("AR","MA","S_AR","S_MA","P","D","S_D")
arima_mod_str <- lapply(1:nrow(fitted_mod_spec),FUN=function(i){paste(c(fitted_mod_spec[i,]),collapse="_")})
fitted_mod_spec$mod <- as.character(arima_mod_str)
fitted_mod_spec$mod_fac <- as.factor(fitted_mod_spec$mod)

#read.table(file=paste("fitted_mod_spec_tb","_",out_suffix,".txt",)

write.table(fitted_mod_spec,file=paste("fitted_mod_spec_tb","_",out_suffix,".txt",col.names=T,row.names=F,sep=","))

## Now plot
            
p1 <- histogram(fitted_mod_spec$AR) #how to present everything at once?? should this be transposed?
p2 <- histogram(fitted_mod_spec$MA)
p3 <- histogram(fitted_mod_spec$P)
p4 <- histogram(fitted_mod_spec$D)
p3 <- histogram(fitted_mod_spec$mod_fac)

#p3 <- histogram(fitted_mod_spec$mod)

p3 <- histogram(fitted_mod_spec$mod_fac)
dat_arima <- fitted_mod_spec
coordinates(dat_arima) <- coordinates(pix_val)

#rasterize(dat_arima)
r_ar <- rasterize(dat_arima,rast_ref,field="AR") #this is the prediction from lm model
r_ma <- rasterize(dat_arima,rast_ref,field="MA") #this is the prediction from lm model
r_p <- rasterize(dat_arima,rast_ref,field="P") #this is the prediction from lm model
r_d <- rasterize(dat_arima,rast_ref,field="D") #this is the prediction from lm model

r_arima_s <- stack(r_ar,r_ma,r_p,r_d)
names(r_arima_s) <- c("AR","MA","P","D")
plot(r_arima_s)

plot(r_ar,col=c("red","blue","green","grey","black"),main="AR")
plot(r_ma,col=c("red","blue","green","grey","black"),main="MA")

###############


#pred_spat_mle_chebyshev
#pred_spat_mle_chebyshev <- load_obj(file.path("/home/parmentier/Data/Space_beats_time/output_EDGY_predictions_03092015",
#                                              "spat_reg_obj_mle_Chebyshev_t_156EDGY_predictions_03092015.RData"))

path_pred_spat_mle <- ("/home/parmentier/Data/Space_beats_time/output_EDGY_predictions_03092015")
spat_pred_rast_mle <- stack(list.files(path=path_pred_spat_mle,pattern="r_spat_pred_mle_Chebyshev_t_.*.EDGY_predictions_03092015.rst$",full.names=T))
#spat_pred_rast_mle <- stack(lapply(pred_spat_mle_chebyshev,FUN=function(x){x$raster_pred})) #get stack of predicted images
#spat_res_rast_mle <- stack(lapply(pred_spat_mle_chebyshev,FUN=function(x){x$raster_res})) #get stack of predicted images
#levelplot(spat_res_rast_mle,col.regions=matlab.like(25)) #view the four predictions using mle spatial reg.
projection(spat_pred_rast_mle) <- CRS_WGS84

r_temp_s <- r_pred #Now temporal predicitons based on ARIMA!!!
temp_pred_rast <- r_temp_s
projection(temp_pred_rast) <- CRS_WGS84
#r_temp_s <- spat_pred_rast_mle #Now temporal predicitons based on ARIMA!!!

############ PART V COMPARE MODELS IN TERM OF PREDICTION ACCURACY #################

r_huric_w <- subset(r_stack,153:156)
#r_huric_w <- crop(r_huric_w,rast_ref)

#r_winds_m <- crop(winds_wgs84,res_temp_s) #small test window
res_temp_s <- temp_pred_rast - r_huric_w
res_spat_s <- spat_pred_rast_mle - r_huric_w
#pred_spat_mle_Chebyshev_test <-load_obj("pred_spat_mle_chebyshev_EDGY_predictions_03092015.RData")

names(res_temp_s) <- sub("predictions","residuals",names(res_temp_s))
#names(res_spat_mle_s) <- sub("predictions","residuals",names(res_spat_mle_s))
names(res_spat_s) <- sub("predictions","residuals",names(res_spat_s))

#debug(calc_ac_stat_fun)
projection(rast_ref) <- CRS_WGS84
#r_zones <- raster(l_rast[22])
z_winds <- subset(s_raster,"z_winds")
#projection(r_winds) <- CRS_WGS84
#reproject data to latlong WGS84 (EPSG4326)
#r_winds <- raster(winds_zones_fname)
#projection(r_winds) <- proj_modis_str 
#r_winds_m <- projectRaster(from=r_winds,res_temp_s,method="ngb") #Check that it is using ngb
             
#r_in <-stack(l_rast)
projection(s_raster) <- CRS_WGS84
#r_results <- stack(s_raster,temp_pred_rast,spat_pred_rast_mle,spat_pred_rast_gmm,res_temp_s,res_spat_mle_s,res_spat_gmm_s)
#r_results <- stack(s_raster,r_winds_m,temp_pred_rast,spat_pred_rast_gmm,res_temp_s,res_spat_gmm_s)
#r_results <- stack(s_raster,r_winds_m,temp_pred_rast,spat_pred_rast_s,res_temp_s,res_spat_s)

#dat_out <- as.data.frame(r_results)
#dat_out <- na.omit(dat_out)
#write.table(dat_out,file=paste("dat_out_",out_suffix,".txt",sep=""),
#            row.names=F,sep=",",col.names=T)

levelplot(spat_pred_rast_mle,col.regions=rev(terrain.colors(255))) #view the four predictions using mle spatial reg.
levelplot(temp_pred_rast,col.regions=rev(terrain.colors(255))) #view the four predictions using mle spatial reg.
levelplot(r_huric_w,col.regions=rev(terrain.colors(255))) #view the four predictions using mle spatial reg.

levelplot(res_temp_s,col.regions=matlab.like(255)) #view the four predictions using mle spatial reg.
levelplot(res_spat_s,col.regions=matlab.like(255)) #view the four predictions using mle spatial reg.

res_temp_s <- temp_pred_rast - r_huric_w
res_spat_s <- spat_pred_rast_mle - r_huric_w
histogram(res_temp_s)
histogram(res_spat_s)

r_dif <- temp_pred_rast - spat_pred_rast_mle
levelplot(r_dif,col.regions=matlab.like(255))


writeRaster(res_temp_s,)
### Now accuracy assessment using MAE

out_suffix_s <- paste("temp_",out_suffix,sep="_")
#debug(calc_ac_stat_fun)
projection(rast_ref) <- CRS_WGS84
projection(spat_pred_rast_mle) <- CRS_WGS84
projection(z_winds) <- CRS_WGS84 #making sure proj4 representation of projections are the same

ac_temp_obj <- calc_ac_stat_fun(r_pred_s=temp_pred_rast,r_var_s=r_huric_w,r_zones=z_winds,
                                file_format=file_format,out_suffix=out_suffix_s)
#out_suffix_s <- paste("spat_",out_suffix,sep="_")  
#ac_spat_obj <- calc_ac_stat_fun(r_pred_s=spat_pred_rast,r_var_s=r_huric_w,r_zones=rast_ref,
#                                file_format=file_format,out_suffix=out_suffix_s)

out_suffix_s <- paste("spat_mle",out_suffix,sep="_")  
ac_spat_mle_obj <- calc_ac_stat_fun(r_pred_s=spat_pred_rast_mle,r_var_s=r_huric_w,r_zones=z_winds,
                                file_format=file_format,out_suffix=out_suffix_s)

#mae_tot_tb <- t(rbind(ac_spat_obj$mae_tb,ac_temp_obj$mae_tb))
#mae_tot_tb <- (cbind(ac_spat_obj$mae_tb,ac_temp_obj$mae_tb))
mae_tot_tb <- (cbind(ac_spat_mle_obj$mae_tb,ac_temp_obj$mae_tb))

mae_tot_tb <- as.data.frame(mae_tot_tb)
row.names(mae_tot_tb) <- NULL
names(mae_tot_tb)<- c("spat_reg","temp")
mae_tot_tb$time <- 1:4

plot(spat_reg ~ time, type="b",col="cyan",data=mae_tot_tb,ylim=c(0,1800))
lines(temp ~ time, type="b",col="magenta",data=mae_tot_tb)
write.table(mae_tot_tb,file=paste("mae_tot_tb","_",out_suffix,".txt",sep=""))
legend("topleft",legend=c("spat","temp"),col=c("cyan","magenta"),lty=1)
title("Overall MAE for spatial and temporal models for GMM") #Note that the results are different than for ARIMA!!!

#### BY ZONES ASSESSMENT

mae_zones_tb <- rbind(ac_spat_mle_obj$mae_zones_tb[1:3,],
                      ac_temp_obj$mae_zones_tb[1:3,])
mae_zones_tb <- as.data.frame(mae_zones_tb)
mae_zones_tb$method <- c("spat_reg","spat_reg","spat_reg","temp","temp","temp")
names(mae_zones_tb) <- c("zones","pred1","pred2","pred3","pred4","method")

write.table(mae_zones_tb,file=paste("mae_zones_tb","_",out_suffix,".txt",sep=""))
plot(as.numeric(mae_zones_tb[6,2:5]),type="b",ylim=c(700,2000),col="red")
lines(as.numeric(mae_zones_tb[3,2:5]),type="b")

mydata<- mae_zones_tb
dd <- do.call(make.groups, mydata[,-ncol(mydata)]) 
#dd$lag <- mydata$lag 
dd$zones <- mydata$zones
dd$method <- mydata$method
#drop first four rows
dd <- dd[7:nrow(dd),]

xyplot(data~which |zones,group=method,data=dd,type="b",xlab="year",ylab="NDVI",
       strip = strip.custom(factor.levels=c("z3","z4","z5")),
      auto.key = list("topright", corner = c(0,1),# col=c("black","red"),
                     border = FALSE, lines = TRUE,cex=1.2)
)

#Very quick and dirty plot
#time <-1:4
#x <- as.numeric(mae_zones_tb[1,3:5])
#plot(x~time, type="b",col="magenta",lty=1,ylim=c(400,2000),ylab="MAE for NDVI")
#x <- as.numeric(mae_zones_tb[2,2:5])
#lines(x~time, type="b",lty=2,col="magenta")
#add temporal
#x <- as.numeric(mae_zones_tb[3,2:5]) #zone 4
#lines(x~time,, type="b",col="cyan",lty=1,ylim=c(400,2000))
#x <- as.numeric(mae_zones_tb[4,2:5]) #zone 5
#lines(x~time, type="b",lty=2,col="cyan")
#legend("topleft",legend=c("spat zone 4","spat zone 5","temp zone 4","temp zone 5"),
#        col=c("magenta","magenta","cyan","cyan"),lty=c(1,2,1,2))
#title("MAE per wind zones for spatial and temporal models")

### Use ARIMA predions instead of lm temporal pred...

#...add here


### more advanced plot to fix later....
#mae_val <- (as.vector(as.matrix(mae_zones_tb[,2:5])))
#avg_ac_tb <- as.data.frame(mae_val)

# avg_ac_tb$metric <- rep("mae",length(mae_val))
# avg_ac_tb$zones <- rep(c(3,4,5),4)
# avg_ac_tb$time <- c(rep(1,6),rep(2,6),rep(3,6),rep(4,6))
# avg_ac_tb$method <- rep(c("spat_reg","spat_reg","spat_reg","arima","arima","arima"),4)
# names(avg_ac_tb)[1]<- "ac_val"
# names_panel_plot <- c("time -1","time +1","time +2","time +3")
# p <- xyplot(ac_val~zones|time, # |set up pannels using method_interp
#             group=method,data=avg_ac_tb, #group by model (covariates)
#             main="Average MAE by winds zones and time step ",
#             type="b",as.table=TRUE,
#             #strip = strip.custom(factor.levels=c("time -1","time +1","time +2","time +3")),
#             strip=strip.custom(factor.levels=names_panel_plot),
#             index.cond=list(c(1,2,3,4)), #this provides the order of the panels)
#             pch=1:length(avg_ac_tb$method),
#             par.settings=list(superpose.symbol = list(
#               pch=1:length(avg_ac_tb$method))),
#             auto.key=list(columns=1,space="right",title="Model",cex=1),
#             #auto.key=list(columns=5),
#             xlab="Winds zones",
#             ylab="MAE for NDVI")
# print(p)



################### END OF SCRIPT ################