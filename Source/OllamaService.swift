// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Foundation

/// A service that communicates with Ollama API to get text completions
class OllamaService {
    private let model: String
    private let baseURL: URL
    private let session: URLSession
    
    /// Initialize the Ollama service with a specific model
    /// - Parameter model: The name of the Ollama model to use (e.g., "llama2", "gemma")
    /// - Parameter baseURLString: The base URL for the Ollama API (default: "http://localhost:11434/api")
    init(model: String, baseURLString: String = "http://localhost:11434/api") {
        self.model = model
        self.baseURL = URL(string: baseURLString)!
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0 // 5 second timeout
        self.session = URLSession(configuration: config)
    }
    
    /// Generate a completion for the given context
    /// - Parameters:
    ///   - context: The text context to generate a completion for
    ///   - completion: A callback that will be called with the generated text or an error
    func generateCompletion(context: String, completion: @escaping (String?, Error?) -> Void) {
        // Create the URL for the generate endpoint
        let url = baseURL.appendingPathComponent("generate")
        
        // Create the request body
        let requestBody: [String: Any] = [
            "model": model,
            "prompt": context,
            "stream": false,
            "options": [
                "temperature": 0.1,
                "top_p": 0.9,
                "max_tokens": 20
            ]
        ]
        
        // Convert the request body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(nil, NSError(domain: "OllamaService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request"]))
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Send the request
        let task = session.dataTask(with: request) { data, response, error in
            // Check for errors
            if let error = error {
                completion(nil, error)
                return
            }
            
            // Check for valid data
            guard let data = data else {
                completion(nil, NSError(domain: "OllamaService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            // Parse the response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let responseText = json["response"] as? String {
                    // Extract the first line or sentence as the suggestion
                    let suggestion = self.extractSuggestion(from: responseText)
                    completion(suggestion, nil)
                } else {
                    completion(nil, NSError(domain: "OllamaService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
                }
            } catch {
                completion(nil, error)
            }
        }
        
        task.resume()
    }
    
    /// Extract a clean suggestion from the model's response
    /// - Parameter text: The raw text from the model
    /// - Returns: A cleaned up suggestion suitable for autocomplete
    private func extractSuggestion(from text: String) -> String {
        // Remove any leading/trailing whitespace
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If there are multiple lines, just take the first one
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        
        // If there are multiple sentences, just take the first one
        let firstSentence = firstLine.components(separatedBy: ".").first ?? ""
        
        // Limit the length to a reasonable size for autocomplete
        let maxLength = 30
        if firstSentence.count > maxLength {
            return String(firstSentence.prefix(maxLength))
        }
        
        return firstSentence
    }
}
