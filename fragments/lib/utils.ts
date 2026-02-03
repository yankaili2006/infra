import { type ClassValue, clsx } from "clsx"
import { twMerge } from "tailwind-merge"

/**
 * Merge Tailwind CSS classes with clsx
 * This is a standard utility function for combining className strings
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Check if a file path exists in an array of file objects
 * Used for file management in the chat interface
 */
export function isFileInArray(
  filePath: string,
  files: Array<{ file_path: string; file_content: string }>
): boolean {
  return files.some((file) => file.file_path === filePath)
}
