library("shiny")


shinyServer(function(input, output) {
	
	
	output$load1 <- renderPlot({ 
		par(bg = rgb(red=1, green=1, blue=1, alpha=0, maxColorValue = 1))
		
		processes<-list.files("/home/ubuntu/imputations/")
		totalProcesses <- length(processes)
		runningProcesses<-0
		remoteRunningProcesses<-0
		for(process in processes){
			status_file<-paste("/home/ubuntu/imputations/",process,"/job_status.txt",sep="")
			if(file.exists(status_file)){
				jobStatus<-read.table(status_file,stringsAsFactors=FALSE,header=FALSE,sep="\t")[1,1]
				if(jobStatus=="Job is running"){
					runningProcesses<-runningProcesses+1
				}
				if(jobStatus=="Job is remote-running"){
					remoteRunningProcesses<-remoteRunningProcesses+1
				}
				
			}
		}
		
# 		remoteRunningProcesses<-2
# 		runningProcesses<-1
# 		totalProcesses<-6
		currentLoad<-matrix(c(runningProcesses,remoteRunningProcesses,totalProcesses-remoteRunningProcesses-runningProcesses),ncol=1)
		barplot(currentLoad,xlim=c(0,8),ylim=c(0,2),main="",horiz=T,xaxt="n",col=c("grey20","grey40","grey70"))
		axis(side=1,at=c(0,1,3,5),labels=c("0","1","3","5"))
		title(xlab="imputations")
		abline(v=1,lty=2)
		abline(v=3,lty=2)
		text(3.02,1.3,adj=0,label="Max queue")
		text(1.02,1.3,adj=0,label="Max running")
		legend("topright",pch=15,col=c("grey20","grey40","grey70"),legend=c("Running","Remote-running","Queued"))
		
	})
	

	
})


