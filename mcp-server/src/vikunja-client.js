/**
 * Vikunja API Client
 *
 * HTTP client for interacting with Vikunja REST API.
 *
 * @license AGPL-3.0
 */

import fetch from 'node-fetch';
import { createLogger } from './logger.js';

const logger = createLogger();

export class VikunjaClient {
  constructor({ baseUrl, token }) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.token = token;
  }

  /**
   * Make an authenticated request to Vikunja API
   */
  async request(method, endpoint, body = null) {
    const url = `${this.baseUrl}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
    };

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const options = {
      method,
      headers,
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    logger.debug(`API Request: ${method} ${endpoint}`);

    try {
      const response = await fetch(url, options);

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API Error (${response.status}): ${errorText}`);
      }

      // Handle empty responses (e.g., DELETE)
      const text = await response.text();
      return text ? JSON.parse(text) : { success: true };
    } catch (error) {
      logger.error(`API request failed: ${method} ${endpoint}`, {
        error: error.message,
      });
      throw error;
    }
  }

  // ===========================================================================
  // Projects
  // ===========================================================================

  /**
   * List all projects
   */
  async listProjects() {
    return this.request('GET', '/projects');
  }

  /**
   * Get a specific project
   */
  async getProject(projectId) {
    return this.request('GET', `/projects/${projectId}`);
  }

  /**
   * Create a new project
   */
  async createProject({ title, description = '' }) {
    return this.request('POST', '/projects', {
      title,
      description,
    });
  }

  // ===========================================================================
  // Tasks
  // ===========================================================================

  /**
   * List tasks, optionally filtered by project
   */
  async listTasks(projectId = null, done = null) {
    let endpoint = '/tasks/all';
    const params = new URLSearchParams();

    if (projectId) {
      endpoint = `/projects/${projectId}/tasks`;
    }

    if (done !== null) {
      params.append('filter_done', done.toString());
    }

    const queryString = params.toString();
    if (queryString) {
      endpoint += `?${queryString}`;
    }

    return this.request('GET', endpoint);
  }

  /**
   * Get a specific task
   */
  async getTask(taskId) {
    return this.request('GET', `/tasks/${taskId}`);
  }

  /**
   * Create a new task
   */
  async createTask({ title, project_id, description = '', priority = 0, due_date = null }) {
    const task = {
      title,
      description,
      priority,
    };

    if (due_date) {
      task.due_date = due_date;
    }

    return this.request('PUT', `/projects/${project_id}/tasks`, task);
  }

  /**
   * Update an existing task
   */
  async updateTask(taskId, updates) {
    // First get the current task to merge with updates
    const currentTask = await this.getTask(taskId);

    const updatedTask = {
      ...currentTask,
      ...updates,
    };

    return this.request('POST', `/tasks/${taskId}`, updatedTask);
  }

  /**
   * Delete a task
   */
  async deleteTask(taskId) {
    return this.request('DELETE', `/tasks/${taskId}`);
  }

  /**
   * Search tasks by title/description
   */
  async searchTasks(query) {
    const params = new URLSearchParams({ s: query });
    return this.request('GET', `/tasks/all?${params.toString()}`);
  }

  // ===========================================================================
  // Labels
  // ===========================================================================

  /**
   * List all labels
   */
  async listLabels() {
    return this.request('GET', '/labels');
  }

  /**
   * Add label to task
   */
  async addLabelToTask(taskId, labelId) {
    return this.request('PUT', `/tasks/${taskId}/labels`, {
      label_id: labelId,
    });
  }

  /**
   * Remove label from task
   */
  async removeLabelFromTask(taskId, labelId) {
    return this.request('DELETE', `/tasks/${taskId}/labels/${labelId}`);
  }

  // ===========================================================================
  // User
  // ===========================================================================

  /**
   * Get current user info
   */
  async getCurrentUser() {
    return this.request('GET', '/user');
  }

  /**
   * Test API connection
   */
  async testConnection() {
    try {
      await this.request('GET', '/info');
      return { connected: true };
    } catch (error) {
      return { connected: false, error: error.message };
    }
  }
}
