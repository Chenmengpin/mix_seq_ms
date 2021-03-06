make_PCA_example_figures <- function(cur_expt) {
  #PARAMS
  sat_quantile <- 0.99
  n_genes_schematic <- 1000
  schem_sat_quantile <- 0.97
  
  CL_annotations <- all_CL_features[[cur_expt$expt_name]]
  
  #merge in primary site annotations
  CL_meta <- all_CL_features$metadata
  CL_annotations %<>% left_join(CL_meta, by = 'DEPMAP_ID')
  
  #call BRAF-mut melanomas
  if (cur_expt$drug_name %in% c('trametinib', 'dabrafenib')) {
    CL_annotations %<>% 
      dplyr::mutate(BRAF_mel = factor(ifelse((BRAF_MUT > 0) & (Subtype == 'melanoma'), TRUE, FALSE)))
  }
  
  out_dir <- file.path(results_dir, cur_expt$expt_name)
  limma_res <-  read_rds(file.path(out_dir, 'limma_res.rds'))
  pc_res <- read_rds(file.path(out_dir, 'LFC_PCA_avgcpm.rds'))

  sc_DE <- load_compute_CPM_stats(cur_expt, results_dir, type = 'avg_cpm', prior_counts = globals$pca_prior_cnt)
  
  #scree plot
  data.frame(rank = seq(length(pc_res$sdev)-1), eig = pc_res$sdev[1:length(pc_res$sdev)-1]) %>% 
    ggplot(aes(rank, eig)) + 
    geom_point(alpha = 0.7) +
    ylab('Std. Dev.') +
    xlab('Component rank') +
    theme_Publication()
  ggsave(file.path(fig_dir, sprintf('%s_screeplot.png', cur_expt$expt_name)),
         width = 2.5, height = 2.)
  ggsave(file.path(fig_dir, sprintf('%s_screeplot.pdf', cur_expt$expt_name)),
         width = 2.5, height = 2.)
  
  #make schematic LFC matrix plot
  top_genes <- apply(sc_DE$LFC_mat, 1, sd, na.rm=T) %>% 
    sort(decreasing = TRUE) %>% 
    head(n_genes_schematic) %>% 
    names()
  LFC_mat <- sc_DE$LFC_mat[top_genes,] %>% t() %>% scale(center = F, scale = F) %>% t()
  
  cmax <- max(abs(quantile(LFC_mat, c(1-schem_sat_quantile, schem_sat_quantile), na.rm=T)))
  make_LFC_heatmap(LFC_mat, top_genes, CL_list = NULL, cluster_rows = TRUE,
                   cluster_cols = TRUE,
                   CL_ann_df = NULL,
                   transpose = TRUE, 
                   color_lims = c(-cmax, cmax),
                   show_rownames = FALSE,
                   show_colnames = FALSE,
                   treeheight_row = 0,
                   treeheight_col = 0,
                   fontsize = 7,
                   annotation_legend = FALSE,
                   filename = file.path(fig_dir, sprintf('%s_schematic_heatmap.pdf', cur_expt$expt_name)),
                   width = 3, height = 2.5)
  
  
  scores_df <- pc_res$x %>% as.data.frame() %>% 
    mutate(Gene = as.character(rownames(pc_res$x)))
  df <- data.frame(CCLE_ID = rownames(pc_res$rotation), check.names = F, stringsAsFactors = F) %>% 
    cbind(pc_res$rotation) %>% 
    dplyr::mutate(DEPMAP_ID = celllinemapr::ccle.to.arxspan(CCLE_ID)) %>% 
    dplyr::select(-CCLE_ID) %>% 
    left_join(CL_annotations, by = "DEPMAP_ID")
  
  #make PC1 vs AUC scatterplot
  if (cur_expt$drug_name == 'dabrafenib') {
    df %<>% mutate(type = factor(ifelse(BRAF_mel, 'BRAF_mut_mel', 'other'), levels = c('other', 'BRAF_mut_mel')))
    cur_aes <- ggplot2::aes(fill = type)
  } else if (cur_expt$drug_name == 'trametinib') {
    df %<>% dplyr::mutate(type = ifelse(BRAF_MUT > 0, 'BRAF_mut', 'other'),
                          type = ifelse(type == 'other' & KRAS_MUT > 0, 'KRAS_mut', type))
    cur_aes <- ggplot2::aes(fill = type)
  } else {
    cur_aes <- ggplot2::aes()
  }
  ggplot(df, aes(PC1, 1-AUC_avg)) + 
    geom_point(cur_aes, alpha = 0.75, pch = 21, size = 3) + 
    geom_smooth(method = 'lm') +
    theme_Publication() +
    ylab('Sensitivity (1-AUC)') +
    guides(fill = FALSE)
    # guides(fill = guide_legend(title = element_blank()))
  ggsave(file.path(fig_dir, sprintf('%s_PC1_PRISM_scatter.png', cur_expt$expt_name)), width = 3.25, height = 2.75)
  ggsave(file.path(fig_dir, sprintf('%s_PC1_PRISM_scatter.pdf', cur_expt$expt_name)), width = 3.25, height = 2.75)
  
  #make PC scatter for trametinib            
  if (cur_expt$drug_name == 'trametinib') {
    ggplot(df, aes(PC1, PC2, fill = type)) + 
      geom_point(alpha = 0.75, color = 'black', pch = 21, size = 3) +
      theme_Publication() +
      guides(fill = guide_legend(nrow = 2, title = element_blank()))
    ggsave(file.path(fig_dir, sprintf('%s_PC_scatter.png', cur_expt$expt_name)), width = 3, height = 3)
    ggsave(file.path(fig_dir, sprintf('%s_PC_scatter.pdf', cur_expt$expt_name)), width = 3, height = 3)
    
    #plot PC2 vs SOX10 expression
    GE <- load.from.taiga(data.name='depmap-rnaseq-expression-data-ccd0', data.version=14, data.file='CCLE_depMap_19Q3_TPM_ProteinCoding') %>%
      cdsr::extract_hugo_symbol_colnames()
    
    df %<>% left_join(data_frame(DEPMAP_ID = rownames(GE), SOX10_GE = GE[, 'SOX10']), by = 'DEPMAP_ID')
    df %<>% mutate(melanoma = ifelse(Subtype == 'melanoma', 'melanoma', 'other'))
    ggplot(df, aes(PC2, SOX10_GE, fill = type)) + 
      geom_point(data = df %>% filter(melanoma == 'other'), alpha = 0.75, color = 'black', pch = 21, size = 3) +
      geom_point(data = df %>% filter(melanoma == 'melanoma'), alpha = 0.75, color = 'black', pch = 21, size = 3, stroke = 2.5) +
      theme_Publication() +
      ylab('SOX10 expression\n(log2 TPM)') +
      # scale_fill_manual(values = c(other = 'darkgray', melanoma = 'red')) +
      guides(fill = FALSE)
      # guides(fill = guide_legend(nrow = 1, title = element_blank(), override.aes = list(stroke = 0.5)))
      ggsave(file.path(fig_dir, sprintf('%s_PC_SOX10_scatter.png', cur_expt$expt_name)), width = 3.25, height = 2.75)
      ggsave(file.path(fig_dir, sprintf('%s_PC_SOX10_scatter.pdf', cur_expt$expt_name)), width = 3.25, height = 2.75)
      }
   
}

