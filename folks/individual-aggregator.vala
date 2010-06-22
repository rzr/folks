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

using Folks;
using Gee;
using GLib;

public class Folks.IndividualAggregator : Object
{
  private BackendStore backend_store;
  private HashMap<string, PersonaStore> stores;
  private HashSet<Backend> backends;

  public HashTable<string, Individual> members { get; private set; }

  public signal void individuals_added (GLib.List<Individual> inds);
  public signal void individuals_removed (GLib.List<Individual> inds);
  /* TODO: add a signal for "subcontact went offline/online"? Is that useful
   * enough to bother with? */

  /* FIXME: make this a singleton? */
  public IndividualAggregator () throws GLib.Error
    {
      this.stores = new HashMap<string, PersonaStore> ();
      this.members = new HashTable<string, Individual> (str_hash, str_equal);

      this.backends = new HashSet<Backend> ();

      this.backend_store = new BackendStore ();
      this.backend_store.backend_available.connect (this.backend_available_cb);
      this.backend_store.load_backends ();
    }

  private void backend_available_cb (BackendStore backend_store,
      Backend backend)
    {
      backend.persona_store_added.connect (this.backend_persona_store_added_cb);
      backend.persona_store_removed.connect (
          this.backend_persona_store_removed_cb);
    }

  private void backend_persona_store_added_cb (Backend backend,
      PersonaStore store)
    {
      this.stores.set (this.store_get_full_id (store), store);
      store.personas_added.connect (this.personas_added_cb);
    }

  private void backend_persona_store_removed_cb (Backend backend,
      PersonaStore store)
    {
      store.personas_added.disconnect (this.personas_added_cb);

      /* no need to remove this stores' personas from all the individuals, since
       * they'll do that themselves (and emit their own 'removed' signal if
       * necessary) */

      this.stores.unset (this.store_get_full_id (store));
    }

  private string store_get_full_id (PersonaStore store)
    {
      return store.type_id + ":" + store.id;
    }

  private void personas_added_cb (PersonaStore store,
      GLib.List<Persona> personas)
    {
      var individuals = new GLib.List<Individual> ();
      personas.foreach ((persona) =>
        {
          var p = (Persona) persona;

          /* FIXME: correlate the new personas with each other and
            * the existing personas and existing Individuals;
            * update existing Individuals and create new ones as
            * necessary */

          var grouped_personas = new GLib.List<Persona> ();
          grouped_personas.prepend (p);
          var individual = new Individual (grouped_personas);
          individuals.prepend (individual);
        });

      /* For each of the individuals constructed from the newly added personas,
       * if they don't exist in the aggregator's list of member individuals,
       * add them to it. */
      GLib.List<Individual> new_individuals = null;
      foreach (var i in individuals)
        {
          if (this.members.lookup (i.id) == null)
            {
              i.removed.connect (this.individual_removed_cb);
              new_individuals.prepend (i);
              this.members.insert (i.id, i);
            }
        }

      /* Signal the addition of new individuals to the aggregator */
      if (new_individuals != null)
        {
          new_individuals.reverse ();
          this.individuals_added (new_individuals);
        }
    }

  private void individual_removed_cb (Individual i)
    {
      var i_list = new GLib.List<Individual> ();
      i_list.append (i);

      this.individuals_removed (i_list);
      this.members.remove (i.id);
    }
}
