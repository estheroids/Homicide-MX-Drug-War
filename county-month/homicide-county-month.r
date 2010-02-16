########################################################
#####       Author: Diego Valle Jones              #####
#####       Website: www.diegovalle.net            #####
#####       Date: 2010-Jan-22                      #####
########################################################

#######################################################
#Time series of the monthly homicide rate by county in
#the Mexican states with the highest homicide rates,
#plus Michoacan which had the biggest decrease in
#homicides from 2006-2008
#######################################################
library(ggplot2)
library(Cairo)

source("constants.r")

#;;;;Apply an  artificial correction to the data
#;;;;to prove that Global Warming is happening
#;;;;Oh wait, wrong file

#Draw a multiple lines plot of each narco-state
cleanHom <-  function(df, state) {
  df <- df[grep(state, df$Code), ]
  df <- subset(df, Year.of.Murder != "Total" &
              Year.of.Murder != "No especificado" &
              Month.of.Murder != "Total" &
              Month.of.Murder != "No especificado" &
              County != "No especificado")
  df$Year.of.Murder <- as.numeric(gsub('[[:alpha:]]', '',
                                        df$Year.of.Murder))
  col2cvt <- 5:ncol(df)
  df[is.na(df)] <- 0
  df$Total.Murders <- apply(df[ , col2cvt], 1, sum)
  df$Month.of.Murder <- factor(df$Month.of.Murder)
  #The months are in a weird order, so 04=Abril, etc.
  levels(df$Month.of.Murder) <- c("04","08","12","01","02","07","06","03","05","11","10","09")

  df$Date <- as.Date(paste(df$Month.of.Murder,"/",
                    "01", "/",
                    df$Year.of.Murder, sep =""), "%m/%d/%Y")
  #Make sure we code the dates as the last day of the month
  df$Date <- as.Date(format(df$Date + 31, "%Y%m01"), "%Y%m%d") - 1

  #The data for the last month of 2008 isn't complete
  df <- subset(df, Date < as.Date("12/01/2008", "%m/%d/%Y"))

  #Remove the space that separates the state code from the
  #county code so we can merge the homicide data with the
  #population data
  df$Code <- as.numeric(gsub("[ ]", "", df$Code ))
  df
}

mergeHomPop <- function(df, pop, cutoff) {
  df.pop <- merge(df, pop, by.x=c("Code", "Year.of.Murder"),
        by.y=c("Code", "Year"))
  #Only big counties!
  #Subseting by size doesn't work because populations change
  #over time, so
  #a county that started at 90,000 will be missing half the
  #the observations
  counties100 <- subset(df.pop, Population > cutoff)
  states <- unique(factor(counties100$County.x))
  df.pop <- subset(df.pop, County.x %in% states)

  df.pop$rate <- (df.pop$Total.Murders / df.pop$Population * 100000) * 12
  #since the INEGI in all its wisdom decided to simply delete
  #the rows with no monthly homicides we have to recreate the
  #database to include them
  start <- as.Date("2005/2/01")
  next.mon <- seq(start, length=47, by='1 month')
  period <- next.mon - 1
  dates.df <- data.frame(Date = rep(period,
                                    each = length(states)),
                         County.x = rep(states,
                                        length(states) *
                                        length(period))
                         )
  df.pop <- merge(dates.df, df.pop,
                   by = c("Date", "County.x"),
                   all.x = TRUE)
  #An NA means there were no murders, so we have to change it to 0
  df.pop$rate[is.na(df.pop$rate)] <- 0
  df.pop$Total.Murders[is.na(df.pop$Total.Murders)] <- 0
  df.pop
}

getData <- function(df, pop, state, cutoff){
  hom.clean <- cleanHom(df, state)
  mergeHomPop(hom.clean, pop, cutoff)
}

cleanPop <- function(filename) {
  pop <- read.csv(bzfile(filename))
  pop <- na.omit(pop)
  col2cvt <- 3:ncol(pop)
  pop[,col2cvt] <- lapply(pop[ ,col2cvt],
                          function(x){as.numeric(gsub(" ", "", x))})
  popm <- melt(pop, id = c("Clave", "Entidad.federativa.o.municipio"))
  #remove the space before the county code
  popm$variable <- as.numeric(substring(popm$variable, 2))
  names(popm) <- c("Code", "County", "Year","Population")
  popm
}

drawPlot <- function(df.pop) {
    ggplot(df.pop, aes(Date, rate)) +
      geom_point(aes(size=Total.Murders), color="darkred") +
      facet_wrap(~ County.x, as.table = FALSE, ncol = 1,
                 scale="free_y") +
      scale_x_date() +
      #geom_smooth(se = FALSE) +
      xlab("") + ylab("Homicide rate")
}

#ToDo: figure out why this doesn't work
addvline <- function(op.date) {
  geom_vline(xintercept = op.date, alpha=.4)
}

addtext <- function(p, date, opname){
  p + geom_text(aes(x,y), label = opname,
            data = data.frame(x = date, y = -10),
            size = 3, hjust = 1, vjust = 0)
#  geom_vline(aes(xintercept = date), alpha=.4)
}

#http://stackoverflow.com/questions/2270201/how-to-get-geom-vline-and-facet-wrap-from-ggplot2-to-work-inside-a-function
drawTS <- function(df.pop, dates, text) {
    date.df <- data.frame(d=dates,t=text)
    p <- ggplot(df.pop, aes(Date, rate)) +
      geom_point(aes(size=Total.Murders), color="darkred") +
      facet_wrap(~ County.x, ncol = 1,
                 scale="free_y") +
      scale_x_date() +
      geom_smooth(aes(group = group), se = FALSE) +
      xlab("") + ylab("Homicide rate")
    p <- p + geom_text(aes(x=d,label=t), y=0,
                   data = date.df,
                   size = 3, hjust = 1, vjust = 0)
    p<-p+geom_vline(aes(xintercept=d), data=date.df, alpha=.4)
    #for(i in 1:length(dates)) {
      #If it's not a global variable I get an object not found error
     # temp[i] <<- dates[i]
     # p <- p + geom_text(aes(x,y), label = text[i],
      #            data = data.frame(x = dates[i], y = -10),
      #            size = 3, hjust = 1, vjust = 0) +
      #     geom_vline(xintercept=temp[i], alpha=.4)
    #}
    p
}

createPlot <- function(df.pop, dates, text) {
  df.pop$group <- cutDates(df.pop, dates)
  drawTS(df.pop, dates,text)
}


hom <- read.csv(bzfile("data/county-month.csv.bz2"))
pop <- cleanPop("data/pop.csv.bz2")

#the county must be this big to enter the chart
popsize <- 100000

########################################################
#Finally, the plots
########################################################

#Baja Califronia Norte! as the ICESI would say, hahahaha
bcn.df <- getData(hom, pop, baja.california, popsize)
createPlot(bcn.df, c(op.tij), c("Joint Operation Tijuana"))

dev.print(png, file="output/Baja California.png", width=600, height=600)


#Sonora
son.df <- getData(hom, pop, sonora, popsize)
createPlot(son.df, c(op.son), c("Operation Sonora I"))

dev.print(png, file = "output/Sonora.png", width=600, height=600)


#Chihuahua
chi.df <- getData(hom, pop, chihuahua, popsize)
createPlot(chi.df, c(op.tria.dor, op.chi), c("Joint Operation Triangulo Dorado", "Joint Operation Chihuahua"))

dev.print(png, file = "output/Chihuahua.png", width=600, height=600)


#Michoacán (I hate trying to get emacs and R to understand utf!)
mich.df <- getData(hom, pop, michoacan, popsize)
createPlot(mich.df, c(op.mich), c("Joint Operation Michoacan"))

dev.print(png, file = "output/Michoacan.png", width=600, height=600)


#Sinadroga
sin.df <- getData(hom, pop, sinaloa, popsize)
createPlot(sin.df, c(op.tria.dor, op.sin), c("Joint Operation Triangulo Dorado", "Joint Operation Culiacan-Navolato"))

dev.print(png, file = "output/Sinaloa.png", width=700, height=600)


#Durango
dur.df <- getData(hom, pop, durango, popsize)
createPlot(dur.df, c(op.tria.dor, op.tria.dor.III), c("Joint Operation Triangulo Dorado", "Phase III" ))

dev.print(png, file = "output/Durango.png", width=600, height=600)




#The data for Oaxaca and Guerrero are in another file
hom <- read.csv(bzfile("data/county-month-gue-oax.csv.bz2"))


#Guerrero
gue.df <- getData(hom, pop, guerrero, popsize)
createPlot(gue.df, c(op.gue), c("Joint Operation Guerrero"))

dev.print(png, file = "output/Guerrero.png", width=600, height=600)



#The data for Nuevo Leon and Tamaulipas are in yet another file
hom <- read.csv(bzfile("data/county-month-nl-tam.csv.bz2"))



#Tamaulipas
tam.df <- getData(hom, pop, tamaulipas, popsize)
createPlot(tam.df, c(op.tam.nl), c("Joint Operation Tamaulipas-Nuevo Leon"))

dev.print(png, file = "output/Tamaulipas.png", width=600, height=900)

#Nuevo Leon
nl.df <- getData(hom, pop, nuevo.leon, popsize)
createPlot(nl.df, c(op.tam.nl), c("Joint Operation Tamaulipas-Nuevo Leon"))

dev.print(png, file = "output/Nuevo-Leon.png", width=600, height=900)

