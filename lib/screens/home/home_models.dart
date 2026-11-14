enum PdfViewMode {
  thumbnail, // Grid / Thumbnail view
  list, // List view
}

enum SortType {
  dateDesc, // Newest modified first
  dateAsc, // Oldest modified first
  nameAsc, // Name A to Z
  nameDesc, // Name Z to A
  sizeDesc, // Largest size first
  sizeAsc, // Smallest size first
}

enum FolderSortType {
  nameAsc, // Folder name A to Z
  nameDesc, // Folder name Z to A
  pathAsc, // Folder path A to Z
  pathDesc, // Folder path Z to A
  fileCountDesc, // Most files first
  fileCountAsc, // Fewest files first
  dateDesc, // Newest modified PDF first
  dateAsc, // Oldest modified PDF first
}
