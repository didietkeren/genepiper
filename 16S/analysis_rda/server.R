library(shiny)
library(tidyverse)
library(phyloseq)
library(shinyjs)

shinyServer(
  function(input, output, session) {
    vals <- reactiveValues()
    
    output$dataReady <- reactive(isTruthy(vals$modifiedPhyloseq))
    outputOptions(output, "dataReady", suspendWhenHidden = FALSE)
    
    source("../function_phyloseq.R")
    
    ### Load Data Panel
    source("../server_panel_load_data.R", local = TRUE)
    
    ### Filter Panel
    source("../server_panel_filter.R", local = TRUE)
    
    ### Parameter Panel
    source("../server_panel_parameter.R", local = TRUE)
    
    observe({
      req(vals$filteredPhyloseq)
      vals$modifiedPhyloseq <- NULL
    })
    
    serverTaxRank()
    
    ## General Tab
    # prepareDataButton
    observeEvent(input$prepareDataButton,
                 {
                   vals$prepareDataMessage <- NULL
                   vals$modifiedPhyloseq <- NULL
                   vals$taxRank <- NULL
                   tryCatch(
                     {
                       req(vals$filteredPhyloseq, input$taxRank, input$abundanceType)
                       vals$modifiedPhyloseq <- agglomerateTaxa(vals$filteredPhyloseq, input$taxRank) %>%
                         transformCount(input$abundanceType)
                       vals$taxRank <- input$taxRank
                     },
                     error = function(e) {
                       vals$prepareDataMessage <- "Error: Prepare data error."
                     }
                   )
                 }
    )
    
    output$prepareDataMessage <- renderText(HTML(vals$prepareDataMessage))
    
    ## Table X Tab
    observe({
      hideTab("parametersTabset", "Table X")
      req(vals$modifiedPhyloseq)
      showTab("parametersTabset", "Table X")
    })
    
    # rankFilter
    observe({
      req(vals$taxRank, vals$modifiedPhyloseq)
      choices <- c(rank_names(vals$modifiedPhyloseq), "OTU")
      choices <- choices[1 : which(choices == vals$taxRank)]
      updateSelectInput(session, "rankFilter", choices = choices)
    })
    
    # tableXLabel
    observe({
      vals$tableXChoices <- NULL
      req(input$rankFilter, vals$modifiedPhyloseq)
      choices <- switch(input$rankFilter, 
                        OTU = taxa_names(vals$modifiedPhyloseq), 
                        get_taxa_unique(vals$modifiedPhyloseq, input$rankFilter))
      vals$tableXChoices <- choices
      updateCheckboxGroupInput(session, "tableXLabel", choices = choices, selected = choices)
    })
    
    # tableXSelectAllButton
    observeEvent(input$tableXSelectAllButton,
                 {
                   req(vals$tableXChoices)
                   updateCheckboxGroupInput(session, "tableXLabel", choices = vals$tableXChoices, selected = vals$tableXChoices)
                 }
    )
    
    # tableXClearAllButton
    observeEvent(input$tableXClearAllButton,
                 {
                   req(vals$tableXChoices)
                   updateCheckboxGroupInput(session, "tableXLabel", choices = vals$tableXChoices)
                 }
    )
    
    ## Table Y Tab
    observe({
      hideTab("parametersTabset", "Table Y")
      req(vals$modifiedPhyloseq)
      showTab("parametersTabset", "Table Y")
    })
    
    # tableYLabel
    observe({
      vals$tableYChoices <- NULL
      req(vals$modifiedPhyloseq)
      choices <- sample_variables(vals$modifiedPhyloseq)
      vals$tableYChoices <- choices
      updateCheckboxGroupInput(session, "tableYLabel", choices = choices, selected = choices)
    })
    
    # tableYSelectAllButton
    observeEvent(input$tableYSelectAllButton,
                 {
                   req(vals$tableYChoices)
                   updateCheckboxGroupInput(session, "tableYLabel", choices = vals$tableYChoices, selected = vals$tableYChoices)
                 }
    )
    
    # tableYClearAllButton
    observeEvent(input$tableYClearAllButton,
                 {
                   req(vals$tableYChoices)
                   updateCheckboxGroupInput(session, "tableYLabel", choices = vals$tableYChoices)
                 }
    )
    
    ## RDA Tab
    observe({
      hideTab("parametersTabset", "RDA")
      req(vals$tableX, vals$tableY)
      showTab("parametersTabset", "RDA")
    })
    
    # rdaButton
    observe({
      disable("rdaButton")
      vals$rda <- NULL
      req(vals$tableX, vals$tableY)
      enable("rdaButton")
    })
    
    observeEvent(input$rdaButton,
                 {
                   vals$rda <- NULL
                   vals$rdaMessage <- NULL
                   tryCatch(
                     {
                       req(vals$tableX, vals$tableY)
                       if(is.null(input$rdaFormula) || input$rdaFormula == "") {
                         vals$rda <- vegan::rda(vals$tableX, vals$tableY)
                       } else {
                         vals$rda <- vegan::rda(as.formula(paste0("vals$tableX ~ ", input$ccaFormula)), data = vals$tableY)
                       }
                     },
                     error = function(e) {
                       vals$rdaMessage <- "Error: Incorrect formula or Table Y contains NA values."
                     }
                   )
                 }
    )
    
    output$rdaMessage <- renderPrint(HTML(vals$rdaMessage))
    
    ### Graphic Panel
    source("../server_panel_graphic.R", local = TRUE)
    
    ## Centroid Tab
    observe({
      hideTab("graphicTabset", "Centroid")
      req(!is.na(vals$ccaSummary$centroids))
      showTab("graphicTabset", "Centroid")
    })
    
    ## Plot Axis Tab
    observe({
      req(vals$sampleTable)
      choices <- colnames(vals$sampleTable)
      updateCheckboxGroupInput(session, "plotAxis2d", choices = choices, selected = choices[1 : 2])
    })
    
    ## Envfit Tab
    source("../server_envfit.R", local = TRUE)
    
    ## Legend Tab
    observe({
      req(input$graphicGroupColumn)
      if(input$graphicGroupColumn == "None") {
        hideTab("graphicTabset", "Legend")
      } else {
        showTab("graphicTabset", "Legend")
      }
    })
    
    ### Result
    ## Table X Tab
    observe({
      req(input$parametersTabset == "Table X")
      updateTabsetPanel(session, "resultTabset", selected = "Table X")
    })
    
    # tableX
    output$tableX <- DT::renderDataTable({
      req(vals$tableX)
      DT::datatable(vals$tableX, options = list(scrollX = TRUE))
    })
    
    observe({
      vals$tableX <- NULL
      try(
        {
          req(vals$modifiedPhyloseq, input$rankFilter, length(input$tableXLabel) > 0)
          vals$tableX <- tableX()
        }, silent = TRUE
      )
    })
    
    tableX <- function() {
      subsetTaxaPhyloseq(vals$modifiedPhyloseq, input$rankFilter, input$tableXLabel) %>%
        otuDataFrameWithTaxaRowname(vals$taxRank) %>%
        t() %>%
        as.data.frame()
    }
    
    ## Table Y Tab
    observe({
      req(input$parametersTabset == "Table Y")
      updateTabsetPanel(session, "resultTabset", selected = "Table Y")
    })
    
    # tableY
    output$tableY <- DT::renderDataTable({
      req(vals$tableY)
      DT::datatable(vals$tableY, options = list(scrollX = TRUE))
    })
    
    observe({
      vals$tableY <- NULL
      try(
        {
          req(vals$modifiedPhyloseq, length(input$tableYLabel) > 0)
          vals$tableY <- tableY()
        }, silent = TRUE
      )
    })
    
    tableY <- function() {
      get_variable(vals$modifiedPhyloseq) %>%
        .[, input$tableYLabel]
    }
    
    ## RDA Tab
    observe({
      req(input$parametersTabset == "RDA")
      updateTabsetPanel(session, "resultTabset", selected = "RDA")
    })
    
    observe({
      vals$rdaSummary <- NULL
      req(vals$rda)
      vals$rdaSummary <- vegan:::summary.cca(vals$rda, axes = 100)
    })
    
    ## RDA_Output Tab
    output$rdaOutput <- renderPrint(vals$rda)
    
    output$downloadRDAButton <- downloadHandler("rda.rds", function(file) saveRDS(vals$rda, file))
    
    ## RDA_Taxa Tab
    output$taxaTable <- DT::renderDataTable(
      {
        DT::datatable(vals$taxaTable, options = list(scrollX = TRUE)) %>%
          DT::formatRound(colnames(vals$taxaTable), digits = 4)
      }
    )
    
    observe({
      vals$taxaTable <- NULL
      req(vals$rdaSummary)
      vals$taxaTable <- as.data.frame(vals$rdaSummary$species)
    })
    
    output$downlaodTaxaTableButton <- downloadHandler("rda_taxa.tsv",
                                                      function(file) {
                                                        write.table(vals$taxaTable, file, sep = "\t", quote = FALSE)
                                                      })
    
    ## RDA_Sample Tab
    output$sampleTable <- DT::renderDataTable(
      {
        DT::datatable(vals$sampleTable, options = list(scrollX = TRUE)) %>%
          DT::formatRound(colnames(vals$sampleTable), digits = 4)
      }
    )
    
    observe({
      vals$sampleTable <- NULL
      req(vals$rdaSummary)
      vals$sampleTable <- as.data.frame(vals$rdaSummary$sites)
    })
    
    output$downloadSampleTableButton <- downloadHandler("rda_sample.tsv",
                                                        function(file) {
                                                          write.table(vals$sampleTable, file, sep = "\t", quote = FALSE)
                                                        })
    
    ## RDA_Constraint Tab
    output$constraintTable <- DT::renderDataTable(
      {
        DT::datatable(vals$constraintTable, options = list(scrollX = TRUE)) %>%
          DT::formatRound(colnames(vals$constraintTable), digits = 4)
      }
    )
    
    observe({
      vals$constraintTable <- NULL
      req(vals$rdaSummary)
      vals$constraintTable <- as.data.frame(vals$rdaSummary$constraints)
    })
    
    output$downloadConstraintTableButton <- downloadHandler("rda_constraint.tsv",
                                                            function(file) {
                                                              write.table(vals$constraintTable, file, sep = "\t", quote = FALSE)
                                                            })
    
    ## RDA_Biplot Tab
    output$biplotTable <- DT::renderDataTable(
      {
        DT::datatable(vals$biplotTable, options = list(scrollX = TRUE)) %>%
          DT::formatRound(colnames(vals$biplotTable), digits = 4)
      }
    )
    
    observe({
      vals$biplotTable <- NULL
      req(vals$rdaSummary)
      vals$biplotTable <- as.data.frame(vals$rdaSummary$biplot)
    })
    
    ## RDA_Centroid Tab
    observe({
      hideTab("rdaTabset", "Centroid")
      req(!is.na(vals$rdaSummary$centroids))
      showTab("rdaTabset", "Centroid")
    })
    
    output$centroidTable <- DT::renderDataTable(
      {
        DT::datatable(vals$centroidTable, options = list(scrollX = TRUE)) %>%
          DT::formatRound(colnames(vals$centroidTable), digits = 4)
      }
    )
    
    observe({
      vals$centroidTable <- NULL
      req(vals$rdaSummary)
      vals$centroidTable <- as.data.frame(vals$rdaSummary$centroids)
    })
    
    ## RDA_Permanova Tab
    source("../server_permanova.R", local = TRUE)
    
    ## RDA_Plot Tab
    source("../function_plot.R", local = TRUE)
    output$rdaPlot <- renderPlot(print(vals$formatedGg))
    
    observe({
      vals$formatedGg <- NULL
      req(vals$gg)
      vals$formatedGg <- formatSquareGg(vals$gg)
    })
    
    observe({
      vals$gg <- NULL
      req(vals$rda)
    })
    
    observe({
      vals$gg <- NULL
      req(vals$sampleTable, vals$taxaTable, vals$biplotTable, input$graphicGroupColumn, length(input$plotAxis2d) == 2)
      if(input$graphicGroupColumn == "None") {
        vals$gg <- plotRdaWithoutGroup()
      } else {
        vals$gg <- plotRdaWithGroup()
      }
    })
    
    plotRdaWithoutGroup <- function() {
      gg <- ggplot()
      if(isTruthy(vals$envfit) && input$plotEnvfit) {
        gg <- plotEnvfit(gg, vals$envfit, vals$sampleTable, input$plotAxis2d, vals$envfitFactorLabel, input$envfitVectorLabel,
                         input$envfitFactorDotSize, input$envfitFactorLabelSize, input$envfitVectorLineSize, input$envfitVectorLabelSize)
      }
      gg <- plotBiplot(gg, vals$biplotTable, input$plotAxis2d, input$constrainLineSize, input$constrainLabelSize)
      if(input$plotCentroid) {
        gg <- plotCentroid(gg, vals$centroidTable, input$plotAxis2d, input$labelCentroid, input$centroidSize, input$centroidLabelSize)
      }
      if(input$plotTaxa) {
        taxaTable <- fitCoordinate(vals$taxaTable, vals$sampleTable, input$plotAxis2d)
        gg <- plotDotTaxa(gg, taxaTable, input$plotAxis2d, input$labelTaxa, input$taxaDotSize, input$taxaLabelSize)
      }
      if(input$plotSample) {
        gg <- plotDotSampleWithoutGroup(gg, vals$sampleTable, input$plotAxis2d, input$labelSample, input$sampleDotSize, input$sampleLabelSize)
      }
      gg
    }
    
    plotRdaWithGroup <- function() {
      sampleTable <- sampleTableWithGroup(vals$sampleTable, vals$modifiedPhyloseq, input$graphicGroupColumn)
      gg <- ggplot()
      if(isTruthy(vals$envfit) && input$plotEnvfit) {
        gg <- plotEnvfit(gg, vals$envfit, vals$sampleTable, input$plotAxis2d, vals$envfitFactorLabel, input$envfitVectorLabel,
                         input$envfitFactorDotSize, input$envfitFactorLabelSize, input$envfitVectorLineSize, input$envfitVectorLabelSize)
      }
      gg <- plotBiplot(gg, vals$biplotTable, input$plotAxis2d, input$constrainLineSize, input$constrainLabelSize)
      if(input$plotCentroid) {
        gg <- plotCentroid(gg, vals$centroidTable, input$plotAxis2d, input$labelCentroid, input$centroidSize, input$centroidLabelSize)
      }
      if(input$plotTaxa) {
        taxaTable <- fitCoordinate(vals$taxaTable, vals$sampleTable, input$plotAxis2d)
        gg <- plotDotTaxa(gg, taxaTable, input$plotAxis2d, input$labelTaxa, input$taxaDotSize, input$taxaLabelSize)
      }
      if(input$plotSample) {
        gg <- plotDotSampleWithGroup(gg, sampleTable, input$plotAxis2d, input$graphicGroupColumn, input$labelSample, input$sampleDotSize, input$sampleLabelSize)
      }
      if(input$plotConvexHull) {
        gg <- plotConvexHull(gg, sampleTable, input$plotAxis2d, input$graphicGroupColumn)
      }
      if(input$plotSpider) {
        gg <- plotSpider(gg, sampleTable, input$plotAxis2d, input$graphicGroupColumn, input$spiderLineSize, input$spiderLabelSize)
      }
      if(input$plotEllipse) {
        gg <- plotEllipse(gg, sampleTable, input$plotAxis2d, input$graphicGroupColumn, input$ellipseType, input$ellipseSignif, input$ellipseLineSize)
      }
      gg
    }
    
    plotBiplot <- function(gg, biplotTable, axis, lineSize, labelSize) {
      biplotTable <- rownames_to_column(biplotTable, "Constrain") %>%
        fitCoordinate(vals$sampleTable, axis)
      biplotLabelTable <- nudgeCoordinateReferToOrigin(biplotTable, axis)
      gg +
        geom_segment(aes_string(x = 0, y = 0, xend = axis[1], yend = axis[2]), color = "blue", size = lineSize, arrow = arrow(), data = biplotTable) +
        geom_text(aes_string(x = axis[1], y = axis[2], label = "Constrain"), color = "blue", size = labelSize, data = biplotLabelTable) +
        labs(x = axis[1], y = axis[2])
    }
    
    plotCentroid <- function(gg, centroidTable, axis, label, dotSize, labelSize) {
      centroidTable <- rownames_to_column(centroidTable, "Centroid")
      gg <- gg +
        geom_point(aes_string(x = axis[1], y = axis[2]), color = "blue", shape = 3, size = dotSize, data = centroidTable)
      if(label) {
        gg <- gg +
          ggrepel::geom_text_repel(aes_string(x = axis[1], y = axis[2], label = "Centroid"), color = "blue", size = labelSize, data = centroidTable)
      }
      gg
    }
    
    # downloadDialogButton
    source("../dialog_download.R", local = TRUE)
    
    observeEvent(input$downloadDialogButton, showModal(downloadImageDialog()))
    
    output$imageDownloadButton <- downloadHandler(filename = function() {
      paste0(input$imageFileName, ".png")
    },
                                                  content = function(file) {
                                                    ggsave(file, vals$formatedGg, "png", height = input$imageHeight, width = input$imageWidth)
                                                    removeModal()
                                                  }
    )
  }
)












































