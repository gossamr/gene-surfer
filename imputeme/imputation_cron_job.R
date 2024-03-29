
# 
#Strategy - setup this to run every hour on the hour, 
# 	
#Don't run it as root. THis is better
# crontab -u ubuntu -e
# 50 * * * * Rscript /srv/shiny-server/gene-surfer/imputeme/imputation_cron_job.R > /home/ubuntu/misc_files/cron_logs/`date +\%Y\%m\%d\%H\%M\%S`-impute-cron.log 2>&1


library("mailR")
library("rJava")
library("tools")
source("/srv/shiny-server/gene-surfer/functions.R")



#First checking if node is already at max load (maxImputations)
foldersToCheck<-grep("^imputation_folder",list.files("/home/ubuntu/imputations/"),value=T)
runningJobCount<-0
remoteRunningJobCount<-0
for(folderToCheck in foldersToCheck){
	jobStatusFile<-paste("/home/ubuntu/imputations/",folderToCheck,"/job_status.txt",sep="")
	if(file.exists(jobStatusFile)){
		jobStatus<-read.table(jobStatusFile,stringsAsFactors=FALSE,header=FALSE,sep="\t")[1,1]
		if(jobStatus=="Job is running"){
			runningJobCount<-runningJobCount+1
		}
		if(jobStatus=="Job is remote-running"){
			remoteRunningJobCount<-remoteRunningJobCount+1
		}
	}
}
if(runningJobCount>(maxImputations-1)){
	stop(paste("Found",runningJobCount,"running jobs, and max is",maxImputations,"so doing nothing"))
}


#money saving implementation. If this is hub and there's a job, just send an email an turn on a node server. That way server can run on a small computer
if(serverRole== "Hub"){
	if(length(foldersToCheck) - runningJobCount - remoteRunningJobCount >0){
		mailingResult<-try(stop(),silent=TRUE)
		while(class(mailingResult) == "try-error"){
			mailingResult<-try(send.mail(from = "analyzer6063@gmail.com",
																	 to = "lassefolkersen@gmail.com",
																	 subject = "Imputation is waiting",
																	 body = "There is an imputation waiting. Switch on node",
																	 html=T,
																	 smtp = list(
																	 	host.name = "smtp.gmail.com", 
																	 	port = 465, 
																	 	user.name = "analyzer6063@gmail.com", 
																	 	passwd = "ei1J#bQA^FA$", 
																	 	ssl = TRUE),
																	 authenticate = TRUE,
																	 send = TRUE))
			Sys.sleep(10)
			
		}
		stop("Stopping because the node need to be switched on")
	}
}


#If the computer is not too busy and the serverRole is node - we fetch a job
if(serverRole== "Node"){
	cmd1 <- paste("ssh ubuntu@",hubAddress," ls /home/ubuntu/imputations/",sep="")
	remoteFoldersToCheck<-system(cmd1,intern=T)
	for(remoteFolderToCheck in remoteFoldersToCheck){
		cmd2 <- paste("ssh ubuntu@",hubAddress," cat /home/ubuntu/imputations/",remoteFolderToCheck,"/job_status.txt",sep="")
		jobStatus<-system(cmd2,intern=T)
		#Check if the job is ready
		if(jobStatus=="Job is ready"){
			print(paste("Found job-status file and job is ready",remoteFolderToCheck))
			
			#First write to job-status that now the job is off to a remote server
			cmd3 <- paste("ssh ubuntu@",hubAddress," 'echo Job is remote-running > /home/ubuntu/imputations/",remoteFolderToCheck,"/job_status.txt'",sep="")
			system(cmd3)
			
			#then copy all the files to here
			cmd4 <- paste("scp -r ubuntu@",hubAddress,":/home/ubuntu/imputations/",remoteFolderToCheck," /home/ubuntu/imputations/",remoteFolderToCheck,sep="")
			system(cmd4)
			
			#Then write locally that job is ready
			job_status_file<-paste("/home/ubuntu/imputations/",remoteFolderToCheck,"/job_status.txt",sep="")
			unlink(job_status_file)
			write.table("Job is ready",file=job_status_file,col.names=F,row.names=F,quote=F)
		}
	}
	#Update the local foldersToCheck to reflect new arrivals
	foldersToCheck<-grep("^imputation_folder",list.files("/home/ubuntu/imputations/"),value=T)
}






#Then - no matter the role - we check locally which, if any, folders are ready to run
imputeThisFolder<-NA
for(folderToCheck in foldersToCheck){
	job_status_file<-paste("/home/ubuntu/imputations/",folderToCheck,"/job_status.txt",sep="")
	if(!file.exists(job_status_file)){
		print(paste("Didn't find a job-status file - should probably auto-delete",folderToCheck))
		next
	}
	jobStatus<-read.table(job_status_file,stringsAsFactors=FALSE,header=FALSE,sep="\t")[1,1]
	if(jobStatus=="Job is not ready yet"){
		print(paste("Found job-status file - but job is not ready yet",folderToCheck))
		next
	}
	if(jobStatus=="Job is running"){
		print(paste("Found job-status file - but job is already running",folderToCheck))
		next
	}
	if(jobStatus=="Job is ready"){
		print(paste("Found job-status file and job is ready",folderToCheck))
		unlink(job_status_file)
		write.table("Job is running",file=job_status_file,col.names=F,row.names=F,quote=F)
		imputeThisFolder<-folderToCheck
		break
	}
}
#Stop if none are found
if(is.na(imputeThisFolder)){
	stop("No folders were found to be ready for imputation")
}




#If script is still running, it means there was a job ready for imputation - 
runDir<-paste("/home/ubuntu/imputations/",imputeThisFolder,sep="")
setwd(runDir)
load(paste(runDir,"/variables.rdata",sep=""))
rawdata<-paste(runDir,"/",uniqueID,"_raw_data.txt",sep="")

#if running as node, we also create the output dir already here
if(serverRole== "Node"){
	dir.create(paste("/home/ubuntu/data/",uniqueID,sep=""))
}

#run the imputation
run_imputation(rawdata=rawdata, runDir=runDir)

#summarizing files
summarize_imputation(runDir=runDir,uniqueID=uniqueID,destinationDir="/home/ubuntu/data")


#creating the pData file
timeStamp<-format(Sys.time(),"%Y-%m-%d-%H-%M")
md5sum <- md5sum(paste(uniqueID,"_raw_data.txt",sep=""))
gender<-system(paste("cut --delimiter=' ' -f 5 ",runDir,"/step_1.ped",sep=""),intern=T)
f<-file(paste("/home/ubuntu/data/",uniqueID,"/pData.txt",sep=""),"w")
writeLines(paste(c("uniqueID","filename","email","first_timeStamp","md5sum","gender","protect_from_deletion"),collapse="\t"),f)
writeLines(paste(c(uniqueID,filename,email,timeStamp,md5sum,gender,FALSE),collapse="\t"),f)
close(f)


#Run the genotype extraction routine
crawl_for_snps_to_analyze(uniqueIDs=uniqueID)



#If this is running as a node, we need to copy it back around here
if(serverRole== "Node"){
	#Have to do the * thing, because the directory already exists
	cmd5 <- paste("scp -r /home/ubuntu/data/",uniqueID,"/* ubuntu@",hubAddress,":/home/ubuntu/data/",uniqueID,sep="")
	system(cmd5)
	
	
}


#making a link out to where the data can be retrieved	(different on hub and node)
if(serverRole== "Node"){
	cmd6 <- paste("ssh ubuntu@",hubAddress," 'ln -s /home/ubuntu/data/",uniqueID,"/",uniqueID,".23andme.zip /srv/shiny-server/gene-surfer/www/",uniqueID,".23andme.zip'",sep="")
	system(cmd6)
	
	cmd7 <- paste("ssh ubuntu@",hubAddress," 'ln -s /home/ubuntu/data/",uniqueID,"/",uniqueID,".gen.zip /srv/shiny-server/gene-surfer/www/",uniqueID,".gen.zip'",sep="")
	system(cmd7)
	
	
}else if(serverRole== "Hub"){
	file.symlink(
		from=paste("/home/ubuntu/data/",uniqueID,"/",uniqueID,".23andme.zip",sep=""),
		to=paste("/srv/shiny-server/gene-surfer/www/",uniqueID,".23andme.zip",sep="")
	)
	file.symlink(
		from=paste("/home/ubuntu/data/",uniqueID,"/",uniqueID,".gen.zip",sep=""),
		to=paste("/srv/shiny-server/gene-surfer/www/",uniqueID,".gen.zip",sep="")
	)
}else{stop("very odd")}





print("Getting IP and sending mail")
# ip<-sub("\"}$","",sub("^.+\"ip\":\"","",readLines("http://api.hostip.info/get_json.php", warn=F)))
ip<-"www.impute.me"
location_23andme <- paste(ip,"/www/",uniqueID,".23andme.zip",sep="")
location_gen <- paste(ip,"/www/",uniqueID,".gen.zip",sep="")


message <- paste("<HTML>We have completed imputation of your genome. You can retrieve your imputed genome at this address:<br>",
								 location_23andme,
								 "<br><br>For advanced users, it is also possible to download the <a href=",location_gen,">gen-format files</a></HTML> ",sep="")




mailingResult<-try(stop(),silent=TRUE)
while(class(mailingResult) == "try-error"){
	print(paste("Trying to mail to",email))
	mailingResult<-try(send.mail(from = "analyzer6063@gmail.com",
															 to = email,
															 subject = "Imputation is ready",
															 body = message,
															 html=T,
															 smtp = list(
															 	host.name = "smtp.gmail.com", 
															 	port = 465, 
															 	user.name = "analyzer6063@gmail.com", 
															 	passwd = "ei1J#bQA^FA$", 
															 	ssl = TRUE),
															 authenticate = TRUE,
															 send = TRUE))
	Sys.sleep(10)
	
}

setwd("..")
unlink(runDir,recursive=TRUE)


#also clear the hub imputation_folder if running as node
if(serverRole== "Node"){
	cmd8 <- paste("ssh ubuntu@",hubAddress," 'rm -r /home/ubuntu/imputations/imputation_folder_",uniqueID,"'",sep="")
	system(cmd8)
	
	#also don't leave the finished data here
	unlink(paste("/home/ubuntu/data/",uniqueID,sep=""),recursive=TRUE)
	
}