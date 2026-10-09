## Base type for LFTable's header/body/footer sections: a VBoxContainer, so a section's
## rows stack vertically. LFTable finds each section by class, so a scene can place its
## own sections (to style them) and the table adopts them.
class_name LFTableSection
extends VBoxContainer
