########################################  MODIS AND RASTER PROCESSING #######################################
########################################### Read, project, crop and process rasters #####################################
#This script contains functions to processs raster images.
#AUTHOR: Benoit Parmentier                                                                       
#DATE: 09/11/2013                                                                                
#PROJECT: None, general utility functions                                 
###################################################################################################

### List of functions available:
#
#
#[1] "assign_projection_crs"      "change_names_file_list"     "create__m_raster_region"   
#[4] "create_MODIS_QC_table"      "create_modis_tiles_region"  "define_crs_from_extent_fun"
#[7] "import_modis_layer_fun"     "__raster_list"       "qc_valid_modis_fun"        
#[10] "screening_val_r_stack_fun" 

###Loading R library and packages                                                      
#library(gtools)    # loading some useful tools 

library(sp)
library(raster)
library(rgdal)
require(rgeos)
library(BMS) #contains hex2bin and bin2hex
library(bitops)
require(RCurl)
require(stringr)
require(XML)

## Function to mosaic modis or other raster images

mosaic_m_raster_list<-function(j,list_param){
  #This functions returns a subset of tiles from the modis grid.
  #Arguments: modies grid tile,list of tiles
  #Output: spatial grid data frame of the subset of tiles
  #Note that rasters are assumed to be in the same projection system!!
  
  #rast_list<-vector("list",length(mosaic_list))
  #for (i in 1:length(mosaic_list)){  
  # read the individual rasters into a list of RasterLayer objects
  # this may be changed so that it is not read in the memory!!!
  
  #parse output...
  
  #j<-list_param$j
  mosaic_list<-list_param$mosaic_list
  out_path<-list_param$out_path
  out_names<-list_param$out_rastnames
  file_format <- list_param$file_format
  NA_flag_val <- list_param$NA_flag_val
  ## Start
  
  input.rasters <- lapply(as.character(mosaic_list[[j]]), raster)
  mosaiced_rast<-input.rasters[[1]]
  
  for (k in 2:length(input.rasters)){
    mosaiced_rast<-mosaic(mosaiced_rast,input.rasters[[k]], fun=mean)
    #mosaiced_rast<-mosaic(mosaiced_rast,raster(input.rasters[[k]]), fun=mean)
  }
  
  data_name<-paste("mosaiced_",sep="") #can add more later...
  #raster_name<-paste(data_name,out_names[j],".tif", sep="")
  raster_name<-paste(data_name,out_names[j],file_format, sep="")
  
  writeRaster(mosaiced_rast, NAflag=NA_flag_val,filename=file.path(out_path,raster_name),overwrite=TRUE)  
  #Writing the data in a raster file format...  
  rast_list<-file.path(out_path,raster_name)
  
  return(rast_list)
}

## Function to reproject and crop modis tile or other raster images

create__m_raster_region <-function(j,list_param){
  #This functions returns a subset of tiles from the modis grdid.
  #Arguments: raster name of the file,reference file with
  #Output: spatial grid data frame of the subset of tiles
  
  ## Parse input arguments
  raster_name <- list_param$raster_name[[j]] #list of raster ot project and crop, this is a list!!
  reg_ref_rast <- list_param$reg_ref_rast #This must have a coordinate system defined!!
  out_rast_name <- list_param$out_rast_name[j]
  NA_flag_val <- list_param$NA_flag_val
  
  ## Start #
  layer_rast<-raster(raster_name)
  new_proj<-projection(layer_rast)                  #Extract current coordinates reference system in PROJ4 format
  region_temp_projected<-projectExtent(reg_ref_rast,CRS(new_proj))     #Project from ref to current region coord. system
  layer_crop_rast<-crop(layer_rast, region_temp_projected) #crop using the extent from the region tile
  #layer_projected_rast<-projectRaster(from=layer_crop_rast,crs=proj4string(reg_outline),method="ngb")
  layer_projected_rast<-projectRaster(from=layer_crop_rast,to=reg_ref_rast,method="ngb")
  
  writeRaster(layer_projected_rast,NAflag=NA_flag_val,filename=out_rast_name,overwrite=TRUE)  
  
  return(out_rast_name)
}

#####

change_names_file_list<-function(list_name,out_suffix,out_prefix,extension,out_path=""){
  #Function to add suffix and prefix to list of file names
  lf_new_names_list<-vector("list",length(list_name)) #this will contain new names for files
  for (i in 1:length(list_name)){
    
    lf_name<-basename(list_name[[i]])
    lf_out_path<-dirname(list_name[[i]])
    data_name<-paste(out_prefix,sub(extension,"",lf_name),"_",sep="") #can add more later...
    raster_name<-paste(data_name,out_suffix, sep="") #out_suffix must include extension!!!
    if((lf_out_path!="") & (out_path=="")){
      lf_new_names_list[[i]]<-file.path(lf_out_path,raster_name)
    }else{
      lf_new_names_list[[i]]<-file.path(out_path,raster_name)
    }
    
  }
  return(unlist(lf_new_names_list))
}

screening_val_r_stack_fun<-function(list_val_range,r_stack){
  #Screening values for a raster stack by providing a valid range. Values outside the valid
  #range are assigned NA. Layers in the stack/brick are only screened if a name valid range is provided.
  #input: list_val_range: list of character strings comma separated
  #        e.g.: "mm_12,-15,50","mm_12,-15,50"
  #               variable name, min value, max value
  #The user must include the name of the variable matching the names in the raster brick/stack.
  #Values are assigned NA if they are less than the mini value or greater than the maximum value.
  #Output: stack with screened values. Note that the original order of layer names is not preserved!!!
  
  ## Parameters: parsing
  
  tab_range_list<-do.call(rbind,as.list(list_val_range))
  
  #tab_range <- strsplit(tab_range_list[[j]],",")
  
  tab_range <- strsplit(tab_range_list,",")
  tab_range <-as.data.frame(do.call(rbind, tab_range))
  names(tab_range)<-c("varname","vmin","vmax")
  tab_range$vmin <- as.numeric(as.character(tab_range$vmin)) #transform to character first to avoid values being considered as factor
  tab_range$vmax <- as.numeric(as.character(tab_range$vmax))
  tab_range$varname <- as.character(tab_range$varname)
  val_rst<-vector("list",nrow(tab_range)) #list of one row data.frame
  
  for (k in 1:nrow(tab_range)){
    #avl<-c(-Inf,tab_range$vmin[k],NA, tab_range$vmax[k],+Inf,NA)   #This creates a input vector...val 1 are -9999, 2 neg, 3 positive
    #avl<-c(tab_range$vmin[k],tab_range$vmax[k],NA)   #This creates a input vector...val 1 are -9999, 2 neg, 3 positive
    
    #rclmat<-matrix(avl,ncol=3,byrow=TRUE)
    #s_raster_r<-raster(r_stack,match(tab_range$varterm[k],names(r_stack))) #select relevant layer from stack
    s_raster_r<-raster(r_stack,match(tab_range$varname[k],names(r_stack)))
    #s_raster_r<-reclassify(s_raster_r,rclmat)  #now reclass values 
    #s_raster_r<-reclassify(s_raster_r,rclmat,include.lowest=TRUE,right=FALSE)  #now reclass values 
    #s_raster_r<-reclassify(s_raster_r,rclmat,include.lowest=FALSE,right=FALSE)  #now reclass values 
    #s_raster_r<-reclassify(s_raster_r,rclmat,include.lowest=TRUE,right=TRUE)  #now reclass values
    #s_raster_r<-reclassify(s_raster_r,rclmat,include.lowest=FALSE,right=TRUE)  #now reclass values
    #r_stack<-dropLayer(r_stack,match(tab_range$varname[k],names(r_stack)))
    s_raster_r[s_raster_r < tab_range$vmin[k]] <- NA #Assign NA if less than the minimum value in the valid range
    s_raster_r[s_raster_r > tab_range$vmax[k]] <- NA #Assign NA if greater than the maxim value in the valid range
    
    names(s_raster_r)<-tab_range$varname[k] #Loss of layer names when using reclass
    val_rst[[k]]<-s_raster_r
  }
  #could be taken out of function for parallelization
  s_rst_m<-stack(val_rst) #This a raster stack with valid range of values
  retained_names<-setdiff(names(r_stack),tab_range$varname)
  r_stack <- dropLayer(r_stack,match(tab_range$varname,names(r_stack)))
  names(r_stack) <-retained_names
  r_stack <- addLayer(r_stack,s_rst_m) #add back layers that were screened out
  
  return(r_stack)
}

define_crs_from_extent_fun<-function(reg_outline,buffer_dist){
  #Screening values for raster stack
  #input: list_val_range: list of character strings comma separated
  #        e.g.: "mm_12,-15,50","mm_12,-15,50"
  #               variable name, min value, max value
  library(rgeos)
  
  #Buffer function not in use yet!! need query for specific matching MODIS tile !!! use gIntersection
  if (buffer_dist!=0){
    reg_outline_dissolved <- gUnionCascaded(reg_outline)  #dissolve polygons
    reg_outline <- gBuffer(reg_outline_dissolved,width=buffer_dist*1000)
  }
  
  #CRS_interp <-"+proj=lcc +lat_1=43 +lat_2=45.5 +lat_0=41.75 +lon_0=-120.5 +x_0=400000 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs";
  reg_centroid <- gCentroid(reg_outline)
  reg_centroid_WGS84 <- spTransform(reg_centroid,CRS_locs_WGS84) #get cooddinates of center of region in lat, lon
  reg_outline_WGS84 <- spTransform(reg_outline,CRS_locs_WGS84) #get cooddinates of center of region in lat, lon
  reg_extent <-extent( reg_outline_WGS84) #get boudning box of extent
  #  xy_latlon<-project(xy, CRS_interp, inv=TRUE) # find lat long for projected coordinats (or pixels...)
  
  #Calculate projection parameters
  reg_lat_1 <- ymin(reg_extent)+((ymax(reg_extent)- ymin(reg_extent))/4)
  reg_lat_2 <- ymax(reg_extent)-((ymax(reg_extent)- ymin(reg_extent))/4)
  
  reg_lon_0 <- coordinates(reg_centroid_WGS84)[1]
  reg_lat_0 <- coordinates(reg_centroid_WGS84)[2]
  reg_x_0 <- 0
  reg_y_0 <- 0
  
  #Add false northing and false easting calucation for y_0,x_0
  #CRS_interp <- paste("+proj=lcc +lat_1=",43," +lat_2=",45.5," +lat_0=",41.75," +lon_0=",-120.5,
  #                    " +x_0=",0,"+y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs")
  
  CRS_interp <- paste("+proj=lcc +lat_1=",reg_lat_1," +lat_2=",reg_lat_2," +lat_0=",reg_lat_0," +lon_0=",reg_lon_0,
                      " +x_0=",reg_x_0," +y_0=",reg_y_0," +ellps=WGS84 +datum=WGS84 +units=m +no_defs",sep="")
  
  reg_outline_interp <- spTransform(reg_outline,CRS(CRS_interp)) #get cooddinates of center of region in lat, lon
  
  #add part to save projected file??
  #return reg_outline!!!
  reg_outline_obj <-list(reg_outline_interp,CRS_interp)
  names(reg_outline_obj) <-c("reg_outline","CRS_interp")
  return(reg_outline_obj)
} 

### Assing projection system to raster layer
assign_projection_crs <-function(i,list_param){
  #assign projection to list of raster
  #proj_str: proj4 information
  #filename: raster file 
  proj_str<-list_param$proj_str
  list_filename<-list_param$list_filename
  
  filename <-list_filename[[i]]
  r<-raster(readGDAL(filename))
  projection(r)<-proj_str
  writeRaster(r,filename=filename,overwrite=TRUE)
}

## Function to  reclass value in 

#qc_valid_modis_fun <-function(qc_valid,rast_qc,rast_var,rast_mask=FALSE,NA_flag_val,out_dir=".",out_rast_name){
#  f_values <- as.data.frame(freq(rast_qc)) # frequency values in the raster...
#  f_values$qc_mask <- as.integer(f_values$value %in% qc_valid)
#  f_values$qc_mask[f_values$qc_mask==0] <- NA
#  
#  r_qc_m <- subs(x=rast_qc,y=f_values,by=1,which=3)
#  rast_var_m <-mask(rast_var,r_qc_m)
#  
#  if(rast_mask==FALSE){
#    raster_name<- out_rast_name
#   writeRaster(rast_var_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
#                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
#    return(rast_var_m)
#  }else{
#    r_stack <-stack(rast_var_m,r_qc_m)
#    raster_name<- out_rast_name
#    writeRaster(r_stack, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
#                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
#    return(r_stack)
#  }
#}

load_obj <- function(f){
  env <- new.env()
  nm <- load(f, env)[1]
  env[[nm]]
}

extract_list_from_list_obj<-function(obj_list,list_name){
  #Create a list of an object from a given list of object using a name prodived as input
  list_tmp<-vector("list",length(obj_list))
  for (i in 1:length(obj_list)){
    tmp<-obj_list[[i]][[list_name]] #double bracket to return data.frame
    list_tmp[[i]]<-tmp
  }
  return(list_tmp) #this is  a data.frame
}

screen_for_qc_valid_fun <-function(i,list_param){
  ##Function to assign NA given qc flag values from MODIS or other raster
  #Author: Benoit Parmentier
  #Created On: 09/20/2013
  #Modified On: 09/20/2013
  
  #Parse arguments:
  
  qc_valid <- list_param$qc_valid # valid pixel values as dataframe
  rast_qc <- list_param$rast_qc[i] #raster with integer values reflecting quality flag layer e.g. day qc
  rast_var <- list_param$rast_var[i] #raster with measured/derived variable e.g. day LST
  rast_mask <- list_param$rast_mask #return raster mask as separate layer, if TRUE then raster is written and returned?
  NA_flag_val <- list_param$NA_flag_val #value for NA
  out_dir <- list_param$out_dir #output dir
  out_suffix <- out_suffix # suffix used for raster files written as outputs
  
  #### Start script:
  
  if(is.character(rast_qc)==TRUE){
    rast_name_qc <- rast_qc
    rast_qc <-raster(rast_qc)
  }
  if(is.character(rast_var)==TRUE){
    rast_name_var <- rast_var
    rast_var<-raster(rast_var)
  }
  
  f_values <- as.data.frame(freq(rast_qc)) # frequency values in the raster...as a dataframe
  f_values$qc_mask <- as.integer(f_values$value %in% qc_valid) # values that should be masked out
  f_values$qc_mask[f_values$qc_mask==0] <- NA #NA for masked out values
  
  #Use "subs" function to assign NA to values that are masked, column 1 contains the identifiers i.e. values in raster
  r_qc_m <- subs(x=rast_qc,y=f_values,by=1,which=3) #Use column labeled as qc_mask (number 3) to assign value
  rast_var_m <-mask(rast_var,r_qc_m)
  
  if(rast_mask==FALSE){  #then only write out variable that is masked out
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")
    writeRaster(rast_var_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    return(raster_name)
  }else{
    raster_name <-basename(sub(extension(rast_name_var),"",rast_name_var))
    raster_name<- paste(raster_name,"_",out_suffix,extension(rast_name_var),sep="")
    writeRaster(rast_var_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    raster_name_qc <-basename(sub(extension(rast_name_qc),"",rast_name_qc))
    raster_name_qc <- paste(raster_name_qc,"_",out_suffix,extension(rast_name_qc),sep="")
    writeRaster(r_qc_m, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name_qc)
                ,bylayer=FALSE,bandorder="BSQ",overwrite=TRUE)
    r_stack_name <- list(raster_name,raster_name_qc)
    names(r_stack_name) <- c("var","mask")
    return(r_stack_name)
  }
}

create_raster_list_from_file_pat <- function(out_suffix_s,file_pat="",in_dir=".",out_prefix="",file_format=".rst"){
  #create a list of raster files to creater R raster stacks
  if(file_pat==""){
    list_raster_name <- list.files(path=in_dir,pattern=paste(out_suffix_s,".*",file_format,"$",sep=""),full.names=T)
  }else{
    list_raster_name <- list.files(path=in_dir,pattern=file_pat,full.names=T)
  }
  dat_list<-c(mixedsort(unlist(list_raster_name)))
  #dat_list <- sub("[.][^.]*$", "", dat_list, perl=TRUE) 
  #writeLines(dat_list,con=paste(out_prefix,out_suffix_s,".rgf",sep=""))
  return(dat_list)
}

### MODIS SPECIFIC FUNCTIONS

create_modis_tiles_region<-function(modis_grid,tiles){
  #This functions returns a subset of tiles from the modis grdi.
  #Arguments: modies grid tile,list of tiles
  #Output: spatial grid data frame of the subset of tiles
  
  h_list<-lapply(tiles,substr,start=2,stop=3) #passing multiple arguments
  v_list<-lapply(tiles,substr,start=5,stop=6) #passing multiple arguments
  
  selected_tiles<-subset(subset(modis_grid,subset = h %in% as.numeric (h_list) ),
                         subset = v %in% as.numeric(v_list)) 
  return(selected_tiles)
}

## function to download modis product??

## For some time the ftp access does not work for MOLT!! now use curl and list from http.

#This function does not work yet i.e. under construction...
modis_product_download <- function(MODIS_product,version,start_date,end_date,list_tiles,file_format,out_dir,temporal_granularity){
  
  ##Functions used in the script
  
  extractFolders=function(urlString) {
    htmlString=getURL(urlString)
    ret=gsub("]", "", str_replace_all(str_extract_all(htmlString, paste('DIR',".([^]]+).", '/\">',sep=""))[[1]], "[a-zA-Z\"= <>/]", ""))
    return(ret[which(nchar(ret)>0)])
  }
  
  extractFiles=function(urlString, selHV) {
    #Slight modifications by Benoit
    #selHV: tiles as character vectors
    #urlString: character vector with url folder to specific dates for product
    
    # get filename strings
    htmlString=getURL(urlString)
    #htmlString=getURL(urlString[2])
    allVec=gsub('\">', '', gsub('<a href=\"', "", str_extract_all(htmlString, paste('<a href=\"',"([^]]+)", '\">',sep=""))[[1]]))
    #allVec=gsub('\">', '', gsub('<a href=\"', "", str_extract_all(htmlString, paste('<a href=\"',"([^]]+)", '\">',sep=""))))
    
    ret=c()
    for (currSel in selHV) {
      ret=c(ret, grep(currSel, allVec, value=TRUE))
    }
    # select specific files
    ret <- paste(urlString,ret,sep="") #append the url of folder
    
    jpg=sapply(ret, FUN=endswith, char=".jpg")
    xml=sapply(ret, FUN=endswith, char=".xml")
    hdf=sapply(ret, FUN=endswith, char=".hdf")
    
    retList=list(jpg=ret[which(jpg)], xml=ret[which(xml)], hdf=ret[which(hdf)])
    return(retList)
  }
  
  endswith=function(x, char) {
    currSub = substr(x, as.numeric(nchar(x)-nchar(char))+1,nchar(x))
    if (currSub==char) {return(TRUE)}
    return(FALSE)
  }
  
  #Generate dates and names for files...?
  
  #step 1: parse input elements
  
  #MODIS_product <- list_param$MODIS_product 
  #start_date <- list_param$start_date 
  #end_date <- list_param$end_date
  #list_tiles<- list_param$list_tiles
  #out_dir<- list_param$out_dir
  
  #MODIS_product <- "MOD11A1.005"
  #start_date <- "2001.01.01"
  #end_date <- "2001.01.05"
  #list_tiles<- c("h08v04","h09v04")
  #out_dir<- "/Users/benoitparmentier/Dropbox/Data/NCEAS/MODIS_processing"
  
  #if daily...,if monthly...,if yearly...
  ## find all 7th of the month between two dates, the last being a 7th.
  #if(temporal_granularity=="Daily"){
  #  d
  #}

  st <- as.Date(start_date,format="%Y.%m.%d")
  en <- as.Date(end_date,format="%Y.%m.%d")
  ll <- seq.Date(st, en, by="1 day")
  dates_queried <- format(ll,"%Y.%m.%d")
  
  url_product <-paste("http://e4ftl01.cr.usgs.gov/MOLT/",MODIS_product,"/",sep="") #URL is a constant...
  #url_product <- file.path("http://e4ftl01.cr.usgs.gov/MOLT/",MODIS_product)
  
  dates_available <- extractFolders(url_product)  #Get the list of available dates for the product
  
  list_folder_dates <- intersect(as.character(dates_queried), as.character(dates_available)) #list of remote folders to access
  #list_folder_dates <-setdiff(as.character(dates_available), as.character(dates_queried))
  
  #step 2: list content of specific day folder to obtain specific file...  #parse by tile name!!!

  url_folders_str <-paste(url_product,list_folder_dates,"/",sep="") #url for the folders matching dates to download
  
  ## loop over
  #debug(extractFiles)
  #generate outdir for each tile!!!
  
  list_folders_files <- vector("list",length(url_folders_str))
  d_files <- vector("list",length(list_folders_files))
  file_format<-c("hdf","xml")
  for (i in 1:length(url_folders_str)){
    list_folders_files[[i]] <- extractFiles(url_folders_str[i], list_tiles)[file_format] 
    #d_files[[i]] <- list_folders_files[[i]][[file_format]]                      
  }
  
  d_files <- as.character(unlist(list_folders_files)) #all hte files to download...
    
  #Step 3: download file to the directory 
  
  #prepare files and directories for download
  out_dir_tiles <- file.path(out_dir,list_tiles)
  list_files_tiles <- vector("list",length(list_tiles))
  for(j in 1:length(out_dir_tiles)){
    if (!file.exists(out_dir_tiles[j])){
      dir.create(out_dir_tiles[j])
    }
    list_files_tiles[[j]] <- grep(pattern=list_tiles[j],x=d_files,value=TRUE) 
  }
    
  #Now download per tiles
  for (j in 1:length(list_files_tiles)){ #loop around tils
    file_items <- list_files_tiles[[j]]
    for (i in 1:length(file_items)){
      file_item <- file_items[i]
      download.file(file_item,destfile=file.path(out_dir_tiles[j],basename(file_item)))      
    }
  }
  
  #Prepare return object: list of files downloaded with http and list downloaded of files in tiles directories
  
  list_files_by_tiles <-mapply(1:length(out_dir_tiles),FUN=list.files,pattern="*.hdf$",path=out_dir_tiles,full.names=T) #Use mapply to pass multiple arguments
  colnames(list_files_by_tiles) <- list_tiles #note that the output of mapply is a matrix
  download_modis_obj <- list(list_files_tiles,list_files_by_tiles)
  names(download_modis_obj) <- c("downloaded_files","list_files_by_tiles")
  return(download_modis_obj)
}

#######
## function to import modis in tif or other format...
import_modis_layer_fun <-function(hdf_file,subdataset,NA_flag,out_rast_name="test.tif",memory=TRUE){
  
  #PARSE input arguments/parameters
  
  modis_subset_layer_Day <- paste("HDF4_EOS:EOS_GRID:",hdf_file,subdataset,sep="")
  r <-readGDAL(modis_subset_layer_Day)
  r  <-raster(r)
  
  if(memory==TRUE){
    return(r)
  }else{
    #Finish this part...write out
    raster_name<- out_rast_name
    writeRaster(r_spat, NAflag=NA_flag_val,filename=raster_name,bylayer=TRUE,bandorder="BSQ",overwrite=TRUE)       
    return(raster_name)
  }  
}

## function to import modis in tif or other format...
import_list_modis_layers_fun <-function(i,list_param){
  
  #PARSE input arguments/parameters
  
  hdf_file <- list_param$hdf_file
  subdataset <- list_param$subdataset
  NA_flag_val <- list_param$NA_flag_val
  out_dir <- list_param$out_dir
  out_suffix <- list_param$out_suffix
  file_format <- list_param$file_format
  scaling_factors <- list_param$scaling_factors
  #Now get file to import
  hdf <-hdf_file[i] # must include input path!!
  modis_subset_layer_Day <- paste("HDF4_EOS:EOS_GRID:",hdf,subdataset,sep="")
  
  r <-readGDAL(modis_subset_layer_Day) 
  r  <-raster(r)
  if(!is.null(scaling_factors)){
    r <- scaling_factors[1]*r + scaling_factors[2]
  }
  #Finish this part...write out
  names_hdf<-as.character(unlist(strsplit(x=basename(hdf), split="[.]")))
  
  char_nb<-length(names_hdf)-2
  names_hdf <- names_hdf[1:char_nb]
  raster_name <- paste(paste(names_hdf,collapse="_"),"_",out_suffix,file_format,sep="")
  
  writeRaster(r, NAflag=NA_flag_val,filename=file.path(out_dir,raster_name),bylayer=TRUE,bandorder="BSQ",overwrite=TRUE)       
  return(file.path(out_dir,raster_name)) 
}

create_MODIS_QC_table <-function(LST=TRUE, NDVI=TRUE){
  #Function to generate MODIS QC  flag table
  #Author: Benoit Parmentier (with some lines from S.Mosher)
  #Date: 09/16/2013
  #Some of the inspiration and code originates from Steve Mosher' s blog:
  #http://stevemosher.wordpress.com/2012/12/05/modis-qc-bits/
  
  list_QC_Data <- vector("list", length=2)
  names(list_QC_Data) <- c("LST","NDVI")
  
  ## PRODUCT 1: LST
  #This can be seen from table defined at LPDAAC: https://lpdaac.usgs.gov/products/modis_products_table/mod11a2
  #LST MOD11A2 has 4 levels/indicators of QA:
  
  ## Generate product table
  if (LST==TRUE){
    QC_Data <- data.frame(Integer_Value = 0:255,
                          Bit7 = NA,Bit6 = NA,Bit5 = NA,Bit4 = NA,Bit3 = NA,Bit2 = NA,Bit1 = NA,Bit0 = NA,
                          QA_word1 = NA,QA_word2 = NA,QA_word3 = NA,QA_word4 = NA)
    #Populate table/data frame
    for(i in QC_Data$Integer_Value){
      AsInt <- as.integer(intToBits(i)[1:8])
      QC_Data[i+1,2:9]<- AsInt[8:1]
    } 
    #Level 1: Overal MODIS Quality which is common to all MODIS product
    QC_Data$QA_word1[QC_Data$Bit1 == 0 & QC_Data$Bit0==0] <- "LST Good Quality"    #(0-0)
    QC_Data$QA_word1[QC_Data$Bit1 == 0 & QC_Data$Bit0==1] <- "LST Produced,Check QA"
    QC_Data$QA_word1[QC_Data$Bit1 == 1 & QC_Data$Bit0==0] <- "Not Produced,clouds"
    QC_Data$QA_word1[QC_Data$Bit1 == 1 & QC_Data$Bit0==1] <- "No Produced, check Other QA"
    
    #Level 2: Information on quality of product (i.e. LST produced, Check QA) for LST
    QC_Data$QA_word2[QC_Data$Bit3 == 0 & QC_Data$Bit2==0] <- "Good Data"
    QC_Data$QA_word2[QC_Data$Bit3 == 0 & QC_Data$Bit2==1] <- "Other Quality"
    QC_Data$QA_word2[QC_Data$Bit3 == 1 & QC_Data$Bit2==0] <- "TBD"
    QC_Data$QA_word2[QC_Data$Bit3 == 1 & QC_Data$Bit2==1] <- "TBD"
    
    #Level 3: Information on quality of of emissitivity 
    QC_Data$QA_word3[QC_Data$Bit5 == 0 & QC_Data$Bit4==0] <- "Emiss Error <= .01"
    QC_Data$QA_word3[QC_Data$Bit5 == 0 & QC_Data$Bit4==1] <- "Emiss Err >.01 <=.02"
    QC_Data$QA_word3[QC_Data$Bit5 == 1 & QC_Data$Bit4==0] <- "Emiss Err >.02 <=.04"
    QC_Data$QA_word3[QC_Data$Bit5 == 1 & QC_Data$Bit4==1] <- "Emiss Err > .04"
    
    #Level 4: Uncertaing for LST error
    QC_Data$QA_word4[QC_Data$Bit7 == 0 & QC_Data$Bit6==0] <- "LST Err <= 1"
    QC_Data$QA_word4[QC_Data$Bit7 == 0 & QC_Data$Bit6==1] <- "LST Err > 2 LST Err <= 3"
    QC_Data$QA_word4[QC_Data$Bit7 == 1 & QC_Data$Bit6==0] <- "LST Err > 1 LST Err <= 2"
    QC_Data$QA_word4[QC_Data$Bit7 == 1 & QC_Data$Bit6==1] <- "LST Err > 4"
    
    list_QC_Data[[1]] <- QC_Data
  }

  ## PRODUCT 2: NDVI
  #This can be seen from table defined at LPDAAC: https://lpdaac.usgs.gov/products/modis_products_table/mod11a2
  
  if(NDVI==TRUE){
    QC_Data <- data.frame(Integer_Value = 0:65535,
                          Bit15 = NA,Bit14 = NA,Bit13 = NA,Bit12 = NA,Bit11 = NA,Bit10 = NA,Bit9 = NA,Bit8 = NA,
                          Bit7 = NA,Bit6 = NA,Bit5 = NA,Bit4 = NA,Bit3 = NA,Bit2 = NA,Bit1 = NA,Bit0 = NA,
                          QA_word1 = NA,QA_word2 = NA,QA_word3 = NA,QA_word4 = NA,
                          QA_word5 = NA,QA_word6 = NA,QA_word7 = NA,QA_word8 = NA,
                          QA_word9 = NA)
    #Populate table...this is extremely slow...change???
    for(i in QC_Data$Integer_Value){
      AsInt <- as.integer(intToBits(i)[1:16]) #16bit unsigned integer
      QC_Data[i+1,2:17]<- AsInt[16:1]
    } 
    
    #Level 1: Overal MODIS Quality which is common to all MODIS product
    QC_Data$QA_word1[QC_Data$Bit1 == 0 & QC_Data$Bit0==0] <- "VI Good Quality"    #(0-0)
    QC_Data$QA_word1[QC_Data$Bit1 == 0 & QC_Data$Bit0==1] <- "VI Produced,check QA"
    QC_Data$QA_word1[QC_Data$Bit1 == 1 & QC_Data$Bit0==0] <- "Not Produced,because of clouds"
    QC_Data$QA_word1[QC_Data$Bit1 == 1 & QC_Data$Bit0==1] <- "Not Produced, other reasons"
    
    #Level 2: VI usefulness (read from right to left)
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==0 & QC_Data$Bit3 == 0 & QC_Data$Bit2==0] <- "Highest quality, 1"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==0 & QC_Data$Bit3 == 0 & QC_Data$Bit2==1] <- "Lower quality, 2"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==0 & QC_Data$Bit3 == 1 & QC_Data$Bit2==0] <- "Decreasing quality, 3 "
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==0 & QC_Data$Bit3 == 1 & QC_Data$Bit2==1] <- "Decreasing quality, 4"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==1 & QC_Data$Bit3 == 0 & QC_Data$Bit2==0] <- "Decreasing quality, 5"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==1 & QC_Data$Bit3 == 0 & QC_Data$Bit2==1] <- "Decreasing quality, 6"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==1 & QC_Data$Bit3 == 1 & QC_Data$Bit2==0] <- "Decreasing quality, 7"
    QC_Data$QA_word2[QC_Data$Bit5 == 0 & QC_Data$Bit4==1 & QC_Data$Bit3 == 1 & QC_Data$Bit2==1] <- "Decreasing quality, 8"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==0 & QC_Data$Bit3 == 0 & QC_Data$Bit2==0] <- "Decreasing quality, 9"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==0 & QC_Data$Bit3 == 0 & QC_Data$Bit2==1] <- "Decreasing quality, 10"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==0 & QC_Data$Bit3 == 1 & QC_Data$Bit2==0] <- "Decreasing quality, 11"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==0 & QC_Data$Bit3 == 1 & QC_Data$Bit2==1] <- "Decreasing quality, 12"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==1 & QC_Data$Bit3 == 0 & QC_Data$Bit2==0] <- "Lowest quality, 13"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==1 & QC_Data$Bit3 == 0 & QC_Data$Bit2==1] <- "Quality so low that not useful, 14"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==1 & QC_Data$Bit3 == 1 & QC_Data$Bit2==0] <- "L1B data faulty, 15"
    QC_Data$QA_word2[QC_Data$Bit5 == 1 & QC_Data$Bit4==1 & QC_Data$Bit3 == 1 & QC_Data$Bit2==1] <- "Not useful/not processed, 16"
    
    # Level 3: Aerosol quantity 
    QC_Data$QA_word3[QC_Data$Bit7 == 0 & QC_Data$Bit6==0] <- "Climatology"
    QC_Data$QA_word3[QC_Data$Bit7 == 0 & QC_Data$Bit6==1] <- "Low"
    QC_Data$QA_word3[QC_Data$Bit7 == 1 & QC_Data$Bit6==0] <- "Average"
    QC_Data$QA_word3[QC_Data$Bit7 == 1 & QC_Data$Bit6==1] <- "High"
    
    # Level 4: Adjacent cloud detected
    QC_Data$QA_word4[QC_Data$Bit8==0] <- "No"
    QC_Data$QA_word4[QC_Data$Bit8==1] <- "Yes"
    
    # Level 5: Atmosphere BRDF correction performed
    QC_Data$QA_word5[QC_Data$Bit9 == 0] <- "No"
    QC_Data$QA_word5[QC_Data$Bit9 == 1] <- "Yes"
    
    # Level 6: Mixed Clouds
    QC_Data$QA_word6[QC_Data$Bit10 == 0] <- "No"
    QC_Data$QA_word6[QC_Data$Bit10 == 1] <- "Yes"
    
    #Level 7: Land/Water Flag (read from right to left)
    QC_Data$QA_word7[QC_Data$Bit13==0 & QC_Data$Bit12 == 0 & QC_Data$Bit11==0] <- "Shallow Ocean"
    QC_Data$QA_word7[QC_Data$Bit13==0 & QC_Data$Bit12 == 0 & QC_Data$Bit11==1] <- "Land"
    QC_Data$QA_word7[QC_Data$Bit13==0 & QC_Data$Bit12 == 1 & QC_Data$Bit11==0] <- "Ocean coastlines and lake shorelines"
    QC_Data$QA_word7[QC_Data$Bit13==0 & QC_Data$Bit12 == 1 & QC_Data$Bit11==1] <- "Shallow inland water"
    QC_Data$QA_word7[QC_Data$Bit13==1 & QC_Data$Bit12 == 0 & QC_Data$Bit11==0] <- "Ephemeral water"
    QC_Data$QA_word7[QC_Data$Bit13==1 & QC_Data$Bit12 == 0 & QC_Data$Bit11==1] <- "Deep inland water"
    QC_Data$QA_word7[QC_Data$Bit13==1 & QC_Data$Bit12 == 1 & QC_Data$Bit11==0] <- "Moderate or continental water"
    QC_Data$QA_word7[QC_Data$Bit13==1 & QC_Data$Bit12 == 1 & QC_Data$Bit11==1] <- "Deep ocean"
    
    # Level 8: Possible snow/ice
    QC_Data$QA_word8[QC_Data$Bit14 == 0] <- "No"
    QC_Data$QA_word8[QC_Data$Bit14 == 1] <- "Yes"
    
    # Level 9: Possible shadow
    QC_Data$QA_word9[QC_Data$Bit15 == 0] <- "No"
    QC_Data$QA_word9[QC_Data$Bit15 == 1] <- "Yes"
    
    list_QC_Data[[2]]<- QC_Data
  }
  
  ## PRODUCT 3: Albedo
  #This can be seen from table defined at LPDAAC: https://lpdaac.usgs.gov/products/modis_products_table/mod11a2
  #To be added...
  
  ###Now return and save object:
  #Prepare object to return
  
  save(list_QC_Data,file= file.path(".",paste("list_QC_Data",".RData",sep="")))
  
  return(list_QC_Data)
}

#Screen data: use only : # level 1: LST Produced good quality, LST Produced other Quality Check QA, 
                         # level 2: good data , Other quality 

#classify_raster_fun <- function(list_rast){
#  library(raster)
#  #raster_data <- list.files(path=getwd())    #promt user for dir containing raster files
#  rast_s <- stack(list_rast)
#  f <- function(x) { rowSums(x >= 4 & x <= 9) }
#  x <- calc(rast_s, f, progress='text', filename='output.tif')
#}



