/*
 * Copyright (C) 2010 Collabora Ltd.
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *       Travis Reitter <travis.reitter@collabora.co.uk>
 */

using GLib;
using Folks;

/**
 * Errors from {@link PersonaStore}s.
 */
public errordomain Folks.PersonaStoreError
{
  /**
   * An argument to the method was invalid.
   */
  INVALID_ARGUMENT,

  /**
   * Creation of a {@link Persona} failed.
   */
  CREATE_FAILED,
}

/**
 * A store for {@link Persona}s.
 *
 * After creating a PersonaStore instance, you must connect to the
 * {@link PersonaStore.personas_changed} signal, //then// call
 * {@link PersonaStore.prepare}, otherwise a race condition may occur between
 * emission of {@link PersonaStore.personas_changed} and your code connecting to
 * it.
 */
public abstract class Folks.PersonaStore : Object
{
  /**
   * Emitted when one or more {@link Persona}s are added to or removed from
   * the store.
   *
   * This will not be emitted until after {@link PersonaStore.prepare} has been
   * called.
   *
   * @param added a list of {@link Persona}s which have been removed
   * @param removed a list of {@link Persona}s which have been removed
   * @param message a string message from the backend, if any
   * @param actor the {@link Persona} who made the change, if known
   * @param reason the reason for the change
   */
  public signal void personas_changed (GLib.List<Persona>? added,
      GLib.List<Persona>? removed,
      string? message,
      Persona? actor,
      Groups.ChangeReason reason);

  /**
   * Emitted when the backing store for this PersonaStore has been removed.
   *
   * At this point, the PersonaStore and all its {@link Persona}s are invalid,
   * so any client referencing it should unreference it.
   *
   * This will not be emitted until after {@link PersonaStore.prepare} has been
   * called.
   */
  public abstract signal void removed ();

  /**
   * The type of PersonaStore this is.
   *
   * This is the same for all PersonaStores provided by a given {@link Backend}.
   *
   * This is guaranteed to always be available; even before
   * {@link PersonaStore.prepare} is called.
   */
  public abstract string type_id { get; protected set; }

  /**
   * The instance identifier for this PersonaStore.
   *
   * Since each {@link Backend} can provide multiple different PersonaStores
   * for different accounts or servers (for example), they each need an ID
   * which is unique within the backend.
   */
  public abstract string id { get; protected set; }

  /**
   * The {@link Persona}s exposed by this PersonaStore.
   */
  public abstract HashTable<string, Persona> personas { get; }

  /**
   * Prepare the PersonaStore for use.
   *
   * This connects the PersonaStore to whichever backend-specific services it
   * requires to be able to provide {@link Persona}s. This should be called
   * //after// connecting to the {@link PersonaStore.personas_changed} signal,
   * or a race condition could occur, with the signal being emitted before your
   * code has connected to it, and {@link Persona}s getting "lost" as a result.
   *
   * This is normally handled transparently by the {@link IndividualAggregator}.
   *
   * If this function throws an error, the PersonaStore will not be functional.
   */
  public abstract async void prepare () throws GLib.Error;

  /**
   * Add a new {@link Persona} to the PersonaStore.
   *
   * The {@link Persona} will be created by the PersonaStore backend from the
   * key-value pairs given in `details`. FIXME: These are backend-specific.
   *
   * If the details are not recognised or are invalid,
   * {@link PersonaStoreError.INVALID_ARGUMENT} will be thrown.
   *
   * @param details a key-value map of details to use in creating the new
   * {@link Persona}
   * @return the new {@link Persona}, or `null` on failure
   */
  public abstract async Persona? add_persona_from_details (
      HashTable<string, Value?> details) throws Folks.PersonaStoreError;

  /**
   * Remove a {@link Persona} from the PersonaStore.
   *
   * It isn't guaranteed that the Persona will actually be removed by the time
   * this asynchronous function finishes. The successful removal of the Persona
   * will be signalled through emission of
   * {@link PersonaStore.personas_changed}.
   *
   * @param persona the {@link Persona} to remove
   */
  public abstract async void remove_persona (Persona persona);
}
